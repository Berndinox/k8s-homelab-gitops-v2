# ── NAT ───────────────────────────────────────────────────────────────────────
# NAT masquerade entfernt — VyOS VM auf VLAN 50 übernimmt NAT am WAN.

# ── RFC1918 Address-List ──────────────────────────────────────────────────────
# Shared by WiFi Guest + Client block rules.
# RouterOS dst_address only takes a single CIDR — address-list is the correct approach.

resource "routeros_ip_firewall_addr_list" "rfc1918" {
  for_each = toset(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])
  list     = "rfc1918"
  address  = each.value
  comment  = "RFC1918 private ranges"
}

# ── NTP Server — MikroTik als NTP-Proxy für interne VLANs ────────────────────
# Clients erhalten die Gateway-IP via DHCP als NTP-Server.
# MikroTik synct extern gegen BEV Wien (Stratum 1) — siehe interfaces.tf.

resource "routeros_system_ntp_server" "main" {
  enabled = true
}

# ── Firewall Filter ───────────────────────────────────────────────────────────
# Regeln werden in der Reihenfolge ausgewertet (top → down).
# Alle Regeln sind via place_before vollständig gekettet — garantierte Reihenfolge.
#
# INPUT:   Router selbst als Ziel (DHCP, DNS, NTP, BGP, MGMT)
# FORWARD: Inter-VLAN-Routing + WAN-Zugang

# ─── INPUT chain ─────────────────────────────────────────────────────────────

resource "routeros_ip_firewall_filter" "input_invalid_drop" {
  chain            = "input"
  connection_state = "invalid"
  action           = "drop"
  comment          = "Drop invalid packets"
  place_before     = routeros_ip_firewall_filter.input_established.id
}

resource "routeros_ip_firewall_filter" "input_established" {
  chain            = "input"
  connection_state = "established,related"
  action           = "accept"
  comment          = "Allow established/related"
  place_before     = routeros_ip_firewall_filter.input_mgmt_full.id
}

resource "routeros_ip_firewall_filter" "input_mgmt_full" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_mgmt}"
  action       = "accept"
  comment      = "MGMT full router access"
  place_before = routeros_ip_firewall_filter.input_dhcp.id
}

resource "routeros_ip_firewall_filter" "input_dhcp" {
  chain        = "input"
  protocol     = "udp"
  dst_port     = "67"
  action       = "accept"
  comment      = "Allow DHCP requests"
  place_before = routeros_ip_firewall_filter.input_dns_udp.id
}

# DNS UDP — alle internen VLANs (10.0.0.0/8)
resource "routeros_ip_firewall_filter" "input_dns_udp" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "udp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS UDP from internal VLANs"
  place_before = routeros_ip_firewall_filter.input_dns_tcp.id
}

# DNS TCP — für DNSSEC / große Antworten
resource "routeros_ip_firewall_filter" "input_dns_tcp" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "tcp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS TCP from internal VLANs (DNSSEC)"
  place_before = routeros_ip_firewall_filter.input_ntp.id
}

# NTP UDP — Clients fragen Gateway als NTP-Server
resource "routeros_ip_firewall_filter" "input_ntp" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "udp"
  dst_port     = "123"
  action       = "accept"
  comment      = "Allow NTP from internal VLANs"
  place_before = routeros_ip_firewall_filter.input_icmp_internal.id
}

# ICMP echo-request von intern — für Gateway-Ping/Troubleshooting
resource "routeros_ip_firewall_filter" "input_icmp_internal" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "icmp"
  icmp_options = "8:0"
  action       = "accept"
  comment      = "Allow ICMP echo-request from internal VLANs"
  place_before = routeros_ip_firewall_filter.input_bgp.id
}

# BGP TCP 179 — nur von Cluster VLAN (Cilium-Peering)
resource "routeros_ip_firewall_filter" "input_bgp" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_cluster}"
  protocol     = "tcp"
  dst_port     = "179"
  action       = "accept"
  comment      = "Allow BGP from Cluster VLAN (Cilium peering)"
  place_before = routeros_ip_firewall_filter.input_drop_all.id
}

resource "routeros_ip_firewall_filter" "input_drop_all" {
  chain   = "input"
  action  = "drop"
  log     = true
  comment = "Drop all other inbound to router"
}

# ─── FORWARD chain ───────────────────────────────────────────────────────────

resource "routeros_ip_firewall_filter" "fwd_invalid_drop" {
  chain            = "forward"
  connection_state = "invalid"
  action           = "drop"
  comment          = "Drop invalid packets"
  place_before     = routeros_ip_firewall_filter.fwd_fasttrack.id
}

# FastTrack — hardware-offloaded established flows (größter Performance-Gewinn auf CRS3xx)
resource "routeros_ip_firewall_filter" "fwd_fasttrack" {
  chain            = "forward"
  connection_state = "established,related"
  action           = "fasttrack-connection"
  hw_offload       = true
  comment          = "FastTrack established/related — hw offload"
  place_before     = routeros_ip_firewall_filter.fwd_established.id
}

resource "routeros_ip_firewall_filter" "fwd_established" {
  chain            = "forward"
  connection_state = "established,related"
  action           = "accept"
  comment          = "Allow established/related forward"
  place_before     = routeros_ip_firewall_filter.fwd_client_cluster.id
}

# Client → Cluster (K8s Services via BGP LB-IPs) — VOR dem RFC1918-Block
resource "routeros_ip_firewall_filter" "fwd_client_cluster" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_client}"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "Client → Cluster (K8s services)"
  place_before  = routeros_ip_firewall_filter.fwd_wifi_block_private.id
}

# WiFi Guest → RFC1918 blockieren (address-list statt multi-value dst_address)
resource "routeros_ip_firewall_filter" "fwd_wifi_block_private" {
  chain             = "forward"
  in_interface      = "${var.bridge_name}.${var.vlan_wifi}"
  dst_address_list  = "rfc1918"
  action            = "drop"
  comment           = "WiFi Guest: block access to private ranges"
  place_before      = routeros_ip_firewall_filter.fwd_wifi_internet.id
  depends_on        = [routeros_ip_firewall_addr_list.rfc1918]
}

resource "routeros_ip_firewall_filter" "fwd_wifi_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_wifi}"
  out_interface = "${var.bridge_name}.${var.vlan_server}"
  action        = "accept"
  comment       = "WiFi Guest → Internet (via VyOS on Server VLAN)"
  place_before  = routeros_ip_firewall_filter.fwd_wifisec_cluster.id
}

# WiFi Secure → Cluster + Internet
resource "routeros_ip_firewall_filter" "fwd_wifisec_cluster" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_wifisec}"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "WiFi Secure → Cluster (K8s services)"
  place_before  = routeros_ip_firewall_filter.fwd_wifisec_internet.id
}

resource "routeros_ip_firewall_filter" "fwd_wifisec_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_wifisec}"
  out_interface = "${var.bridge_name}.${var.vlan_server}"
  action        = "accept"
  comment       = "WiFi Secure → Internet (via VyOS on Server VLAN)"
  place_before  = routeros_ip_firewall_filter.fwd_client_block_private.id
}

# Client → RFC1918 blockieren (außer Cluster — bereits oben erlaubt)
resource "routeros_ip_firewall_filter" "fwd_client_block_private" {
  chain             = "forward"
  in_interface      = "${var.bridge_name}.${var.vlan_client}"
  dst_address_list  = "rfc1918"
  action            = "drop"
  comment           = "Client: block access to private ranges (except Cluster, allowed above)"
  place_before      = routeros_ip_firewall_filter.fwd_client_internet.id
  depends_on        = [routeros_ip_firewall_addr_list.rfc1918]
}

resource "routeros_ip_firewall_filter" "fwd_client_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_client}"
  out_interface = "${var.bridge_name}.${var.vlan_server}"
  action        = "accept"
  comment       = "Client → Internet (via VyOS on Server VLAN)"
  place_before  = routeros_ip_firewall_filter.fwd_cluster_internet.id
}

# Cluster → Internet (Image-Pulls, Updates)
resource "routeros_ip_firewall_filter" "fwd_cluster_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_cluster}"
  out_interface = "${var.bridge_name}.${var.vlan_server}"
  action        = "accept"
  comment       = "Cluster → Internet (via VyOS on Server VLAN)"
  place_before  = routeros_ip_firewall_filter.fwd_mgmt_all.id
}

# MGMT → alles (voller Zugang für Administration)
resource "routeros_ip_firewall_filter" "fwd_mgmt_all" {
  chain        = "forward"
  in_interface = "${var.bridge_name}.${var.vlan_mgmt}"
  action       = "accept"
  comment      = "MGMT → all VLANs"
  place_before = routeros_ip_firewall_filter.fwd_dmz_cluster.id
}

# DMZ → Cluster + Internet (BGP-announced LB-IPs)
resource "routeros_ip_firewall_filter" "fwd_dmz_cluster" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_dmz}"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "DMZ → Cluster (BGP-announced K8s services)"
  place_before  = routeros_ip_firewall_filter.fwd_dmz_internet.id
}

resource "routeros_ip_firewall_filter" "fwd_dmz_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_dmz}"
  out_interface = "${var.bridge_name}.${var.vlan_server}"
  action        = "accept"
  comment       = "DMZ → Internet (via VyOS on Server VLAN)"
  place_before  = routeros_ip_firewall_filter.fwd_server_cluster.id
}

# Server → Cluster + Internet (BGP-announced LB-IPs)
resource "routeros_ip_firewall_filter" "fwd_server_cluster" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_server}"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "Server → Cluster (BGP-announced K8s services)"
  place_before  = routeros_ip_firewall_filter.fwd_server_internet.id
}

resource "routeros_ip_firewall_filter" "fwd_server_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_server}"
  out_interface = "${var.bridge_name}.${var.vlan_server}"
  action        = "accept"
  comment       = "Server → Internet (hairpin via VyOS on same VLAN)"
  place_before  = routeros_ip_firewall_filter.fwd_drop_all.id
}

resource "routeros_ip_firewall_filter" "fwd_drop_all" {
  chain   = "forward"
  action  = "drop"
  log     = true
  comment = "Drop all other inter-VLAN traffic"
}
