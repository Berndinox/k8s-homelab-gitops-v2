# ── NAT ───────────────────────────────────────────────────────────────────────
# NAT masquerade entfernt — VyOS VM auf VLAN 50 übernimmt NAT am WAN.

# ── RFC1918 Address-List ──────────────────────────────────────────────────────
# Used by Guest isolation (match) + internet rule (negated match).
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

# ── Interface Lists — Trust-Hierarchie (higher VLAN → lower VLANs) ──────────
# Used in FORWARD chain: each VLAN may access all VLANs below its trust level.
# VLAN 30 (WiFi Guest) excluded everywhere — fully isolated via rfc1918 drop.
#
# Trust:  200 > 100 > 60 > 50 > 40 > 10    (30 = isolated)

resource "routeros_interface_list" "below_cluster" {
  name    = "below-cluster"
  comment = "VLANs below Cluster (100): wifisec, server, client, dmz"
}

resource "routeros_interface_list_member" "below_cluster_wifisec" {
  list      = routeros_interface_list.below_cluster.name
  interface = "${var.bridge_name}.${var.vlan_wifisec}"
}

resource "routeros_interface_list_member" "below_cluster_server" {
  list      = routeros_interface_list.below_cluster.name
  interface = "${var.bridge_name}.${var.vlan_server}"
}

resource "routeros_interface_list_member" "below_cluster_client" {
  list      = routeros_interface_list.below_cluster.name
  interface = "${var.bridge_name}.${var.vlan_client}"
}

resource "routeros_interface_list_member" "below_cluster_dmz" {
  list      = routeros_interface_list.below_cluster.name
  interface = "${var.bridge_name}.${var.vlan_dmz}"
}

resource "routeros_interface_list" "below_wifisec" {
  name    = "below-wifisec"
  comment = "VLANs below WiFi Secure (60): server, client, dmz"
}

resource "routeros_interface_list_member" "below_wifisec_server" {
  list      = routeros_interface_list.below_wifisec.name
  interface = "${var.bridge_name}.${var.vlan_server}"
}

resource "routeros_interface_list_member" "below_wifisec_client" {
  list      = routeros_interface_list.below_wifisec.name
  interface = "${var.bridge_name}.${var.vlan_client}"
}

resource "routeros_interface_list_member" "below_wifisec_dmz" {
  list      = routeros_interface_list.below_wifisec.name
  interface = "${var.bridge_name}.${var.vlan_dmz}"
}

resource "routeros_interface_list" "below_server" {
  name    = "below-server"
  comment = "VLANs below Server (50): client, dmz"
}

resource "routeros_interface_list_member" "below_server_client" {
  list      = routeros_interface_list.below_server.name
  interface = "${var.bridge_name}.${var.vlan_client}"
}

resource "routeros_interface_list_member" "below_server_dmz" {
  list      = routeros_interface_list.below_server.name
  interface = "${var.bridge_name}.${var.vlan_dmz}"
}

resource "routeros_interface_list" "below_client" {
  name    = "below-client"
  comment = "VLANs below Client (40): dmz"
}

resource "routeros_interface_list_member" "below_client_dmz" {
  list      = routeros_interface_list.below_client.name
  interface = "${var.bridge_name}.${var.vlan_dmz}"
}

# ── Firewall Filter ───────────────────────────────────────────────────────────
# Rules evaluated top → down. All rules chained via place_before.
#
# Trust hierarchy (VLAN number = trust level):
#   200 (MGMT)       → all
#   100 (Cluster)    → 60, 50, 40, 10 + Internet
#    60 (WiFi Sec)   → 50, 40, 10 + Internet
#    50 (Server)     → 40, 10 + Internet
#    40 (Client)     → 10 + Internet + K8s Services (via Cluster)
#    30 (WiFi Guest) → Internet ONLY (fully isolated)
#    10 (DMZ)        → Internet + K8s Services (via Cluster)
#
# INPUT:   Router self (DHCP, DNS, NTP, BGP, MGMT)
# FORWARD: Hierarchical inter-VLAN + internet access

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
  place_before = routeros_ip_firewall_filter.input_bgp_cluster.id
}

# BGP TCP 179 — from Cluster VLAN (Cilium peering)
resource "routeros_ip_firewall_filter" "input_bgp_cluster" {
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
# Hierarchical: higher VLAN → lower VLANs allowed, reverse blocked.
# Internet (non-RFC1918 dst) allowed for all VLANs.
# WiFi Guest (30) fully isolated from all private ranges.

# 1. Drop invalid
resource "routeros_ip_firewall_filter" "fwd_invalid_drop" {
  chain            = "forward"
  connection_state = "invalid"
  action           = "drop"
  comment          = "Drop invalid packets"
  place_before     = routeros_ip_firewall_filter.fwd_fasttrack.id
}

# 2. FastTrack — CPU-based (98DX226S does NOT support FastTrack HW offload)
resource "routeros_ip_firewall_filter" "fwd_fasttrack" {
  chain            = "forward"
  connection_state = "established,related"
  action           = "fasttrack-connection"
  comment          = "FastTrack established/related (CPU — no HW offload on 98DX226S)"
  place_before     = routeros_ip_firewall_filter.fwd_established.id
}

# 3. Accept established/related
resource "routeros_ip_firewall_filter" "fwd_established" {
  chain            = "forward"
  connection_state = "established,related"
  action           = "accept"
  comment          = "Allow established/related forward"
  place_before     = routeros_ip_firewall_filter.fwd_guest_isolate.id
}

# 4. WiFi Guest — block ALL private destinations (complete isolation)
resource "routeros_ip_firewall_filter" "fwd_guest_isolate" {
  chain            = "forward"
  in_interface     = "${var.bridge_name}.${var.vlan_wifi}"
  dst_address_list = "rfc1918"
  action           = "drop"
  comment          = "WiFi Guest: block all private ranges (full isolation)"
  place_before     = routeros_ip_firewall_filter.fwd_internet_all.id
  depends_on       = [routeros_ip_firewall_addr_list.rfc1918]
}

# 5. Internet for all VLANs — non-private destinations
# RouterOS 7 supports "!" negation on address-lists.
resource "routeros_ip_firewall_filter" "fwd_internet_all" {
  chain            = "forward"
  dst_address_list = "!rfc1918"
  action           = "accept"
  comment          = "Internet for all VLANs (non-private destinations via VyOS)"
  place_before     = routeros_ip_firewall_filter.fwd_all_cluster.id
  depends_on       = [routeros_ip_firewall_addr_list.rfc1918]
}

# 6. All → Cluster (K8s services via BGP-announced LB IPs)
resource "routeros_ip_firewall_filter" "fwd_all_cluster" {
  chain         = "forward"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "All VLANs → Cluster (K8s services via BGP)"
  place_before  = routeros_ip_firewall_filter.fwd_mgmt_all.id
}

# 7. MGMT → all (full admin access)
resource "routeros_ip_firewall_filter" "fwd_mgmt_all" {
  chain        = "forward"
  in_interface = "${var.bridge_name}.${var.vlan_mgmt}"
  action       = "accept"
  comment      = "MGMT → all VLANs (admin access)"
  place_before = routeros_ip_firewall_filter.fwd_cluster_down.id
}

# 8. Cluster (100) → lower VLANs (60, 50, 40, 10)
resource "routeros_ip_firewall_filter" "fwd_cluster_down" {
  chain              = "forward"
  in_interface       = "${var.bridge_name}.${var.vlan_cluster}"
  out_interface_list = routeros_interface_list.below_cluster.name
  action             = "accept"
  comment            = "Cluster → lower VLANs (hierarchy)"
  place_before       = routeros_ip_firewall_filter.fwd_wifisec_down.id
}

# 9. WiFi Secure (60) → lower VLANs (50, 40, 10)
resource "routeros_ip_firewall_filter" "fwd_wifisec_down" {
  chain              = "forward"
  in_interface       = "${var.bridge_name}.${var.vlan_wifisec}"
  out_interface_list = routeros_interface_list.below_wifisec.name
  action             = "accept"
  comment            = "WiFi Secure → lower VLANs (hierarchy)"
  place_before       = routeros_ip_firewall_filter.fwd_server_down.id
}

# 10. Server (50) → lower VLANs (40, 10)
resource "routeros_ip_firewall_filter" "fwd_server_down" {
  chain              = "forward"
  in_interface       = "${var.bridge_name}.${var.vlan_server}"
  out_interface_list = routeros_interface_list.below_server.name
  action             = "accept"
  comment            = "Server → lower VLANs (hierarchy)"
  place_before       = routeros_ip_firewall_filter.fwd_client_down.id
}

# 11. Client (40) → lower VLANs (10)
resource "routeros_ip_firewall_filter" "fwd_client_down" {
  chain              = "forward"
  in_interface       = "${var.bridge_name}.${var.vlan_client}"
  out_interface_list = routeros_interface_list.below_client.name
  action             = "accept"
  comment            = "Client → DMZ (hierarchy)"
  place_before       = routeros_ip_firewall_filter.fwd_drop_all.id
}

# 12. Drop all — catch-all with logging
resource "routeros_ip_firewall_filter" "fwd_drop_all" {
  chain   = "forward"
  action  = "drop"
  log     = true
  comment = "Drop all other inter-VLAN traffic"
}
