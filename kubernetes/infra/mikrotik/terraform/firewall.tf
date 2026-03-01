# ── NAT ───────────────────────────────────────────────────────────────────────

resource "routeros_ip_firewall_nat" "masquerade" {
  chain              = "srcnat"
  out_interface      = "${var.bridge_name}.${var.vlan_wan}"
  action             = "masquerade"
  comment            = "Masquerade all traffic to WAN"
}

# ── Firewall Filter ───────────────────────────────────────────────────────────
# Order matters — rules are evaluated top to bottom.
# Strategy:
#   input:   Allow established, MGMT full access, DHCP, DNS, BGP. Drop rest.
#   forward: Allow established, selective inter-VLAN, internet. Drop rest.

# ─── INPUT chain ─────────────────────────────────────────────────────────────

resource "routeros_ip_firewall_filter" "input_established" {
  chain            = "input"
  connection_state = "established,related"
  action           = "accept"
  comment          = "Allow established/related"
  place_before     = routeros_ip_firewall_filter.input_mgmt_full.id
}

resource "routeros_ip_firewall_filter" "input_mgmt_full" {
  chain            = "input"
  in_interface     = "${var.bridge_name}.${var.vlan_mgmt}"
  action           = "accept"
  comment          = "MGMT full router access"
}

resource "routeros_ip_firewall_filter" "input_dhcp" {
  chain        = "input"
  protocol     = "udp"
  dst_port     = "67"
  action       = "accept"
  comment      = "Allow DHCP requests"
}

resource "routeros_ip_firewall_filter" "input_dns_dmz" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_dmz}"
  protocol     = "udp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS from DMZ VLAN"
}

resource "routeros_ip_firewall_filter" "input_dns_server" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_server}"
  protocol     = "udp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS from Server VLAN"
}

resource "routeros_ip_firewall_filter" "input_dns_cluster" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_cluster}"
  protocol     = "udp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS from Cluster VLAN"
}

resource "routeros_ip_firewall_filter" "input_dns_wifi" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_wifi}"
  protocol     = "udp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS from WiFi Guest"
}

resource "routeros_ip_firewall_filter" "input_dns_wifisec" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_wifisec}"
  protocol     = "udp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS from WiFi Secure"
}

resource "routeros_ip_firewall_filter" "input_bgp" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_cluster}"
  protocol     = "tcp"
  dst_port     = "179"
  action       = "accept"
  comment      = "Allow BGP from Cluster VLAN (Cilium peering)"
}

resource "routeros_ip_firewall_filter" "input_icmp_cluster" {
  chain        = "input"
  in_interface = "${var.bridge_name}.${var.vlan_cluster}"
  protocol     = "icmp"
  action       = "accept"
  comment      = "Allow ICMP from Cluster"
}

resource "routeros_ip_firewall_filter" "input_drop_all" {
  chain   = "input"
  action  = "drop"
  comment = "Drop all other inbound to router"
}

# ─── FORWARD chain ───────────────────────────────────────────────────────────

resource "routeros_ip_firewall_filter" "fwd_established" {
  chain            = "forward"
  connection_state = "established,related"
  action           = "accept"
  comment          = "Allow established/related forward"
}

# WiFi Guest → internet only (block to RFC1918)
resource "routeros_ip_firewall_filter" "fwd_wifi_block_private" {
  chain        = "forward"
  in_interface = "${var.bridge_name}.${var.vlan_wifi}"
  dst_address  = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
  action       = "drop"
  comment      = "WiFi Guest: block access to private ranges"
}

resource "routeros_ip_firewall_filter" "fwd_wifi_internet" {
  chain        = "forward"
  in_interface = "${var.bridge_name}.${var.vlan_wifi}"
  out_interface = "${var.bridge_name}.${var.vlan_wan}"
  action       = "accept"
  comment      = "WiFi Guest: allow internet only"
}

# WiFi Secure → internet + cluster
resource "routeros_ip_firewall_filter" "fwd_wifisec_cluster" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_wifisec}"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "WiFi Secure → Cluster (access to K8s services)"
}

resource "routeros_ip_firewall_filter" "fwd_wifisec_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_wifisec}"
  out_interface = "${var.bridge_name}.${var.vlan_wan}"
  action        = "accept"
  comment       = "WiFi Secure → Internet"
}

# Cluster → internet (for pull images, updates etc.)
resource "routeros_ip_firewall_filter" "fwd_cluster_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_cluster}"
  out_interface = "${var.bridge_name}.${var.vlan_wan}"
  action        = "accept"
  comment       = "Cluster → Internet"
}

# MGMT → all
resource "routeros_ip_firewall_filter" "fwd_mgmt_all" {
  chain        = "forward"
  in_interface = "${var.bridge_name}.${var.vlan_mgmt}"
  action       = "accept"
  comment      = "MGMT → all VLANs"
}

# DMZ → Cluster (for BGP-announced LB IPs: MikroTik routes 10.0.10.200/28 via VLAN 100)
resource "routeros_ip_firewall_filter" "fwd_dmz_cluster" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_dmz}"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "DMZ → Cluster (reach BGP-announced K8s services)"
  place_before  = routeros_ip_firewall_filter.fwd_drop_all.id
}

resource "routeros_ip_firewall_filter" "fwd_dmz_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_dmz}"
  out_interface = "${var.bridge_name}.${var.vlan_wan}"
  action        = "accept"
  comment       = "DMZ → Internet"
  place_before  = routeros_ip_firewall_filter.fwd_drop_all.id
}

# Server → Cluster (for BGP-announced LB IPs: MikroTik routes 10.0.50.200/28 via VLAN 100)
resource "routeros_ip_firewall_filter" "fwd_server_cluster" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_server}"
  out_interface = "${var.bridge_name}.${var.vlan_cluster}"
  action        = "accept"
  comment       = "Server → Cluster (reach BGP-announced K8s services)"
  place_before  = routeros_ip_firewall_filter.fwd_drop_all.id
}

resource "routeros_ip_firewall_filter" "fwd_server_internet" {
  chain         = "forward"
  in_interface  = "${var.bridge_name}.${var.vlan_server}"
  out_interface = "${var.bridge_name}.${var.vlan_wan}"
  action        = "accept"
  comment       = "Server → Internet"
  place_before  = routeros_ip_firewall_filter.fwd_drop_all.id
}

# Drop everything else
resource "routeros_ip_firewall_filter" "fwd_drop_all" {
  chain   = "forward"
  action  = "drop"
  comment = "Drop all other inter-VLAN traffic"
}
