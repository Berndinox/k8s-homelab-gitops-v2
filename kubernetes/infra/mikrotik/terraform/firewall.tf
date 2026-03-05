# ── NTP Server — MikroTik as NTP proxy for VLAN 100/200 ─────────────────────
# Clients receive MikroTik IP via DHCP as NTP server.
# MikroTik syncs to BEV Wien (Stratum 1) — see interfaces.tf.
resource "routeros_system_ntp_server" "main" {
  enabled = true
}

# ── Firewall Filter ───────────────────────────────────────────────────────────
# MikroTik is pure L2 — no inter-VLAN routing.
#
# INPUT:   Protect MikroTik management (DHCP, DNS, NTP, MGMT access)
# FORWARD: Drop all — MikroTik does not route between VLANs
#
# Connection tracking is kept only for INPUT (management sessions).
# FORWARD has a single DROP rule — no tracking overhead for switched traffic.

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
  comment      = "MGMT VLAN — full router access"
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

resource "routeros_ip_firewall_filter" "input_dns_udp" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "udp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS UDP from internal VLANs"
  place_before = routeros_ip_firewall_filter.input_dns_tcp.id
}

resource "routeros_ip_firewall_filter" "input_dns_tcp" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "tcp"
  dst_port     = "53"
  action       = "accept"
  comment      = "Allow DNS TCP from internal VLANs (DNSSEC)"
  place_before = routeros_ip_firewall_filter.input_ntp.id
}

resource "routeros_ip_firewall_filter" "input_ntp" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "udp"
  dst_port     = "123"
  action       = "accept"
  comment      = "Allow NTP from internal VLANs"
  place_before = routeros_ip_firewall_filter.input_icmp_internal.id
}

resource "routeros_ip_firewall_filter" "input_icmp_internal" {
  chain        = "input"
  src_address  = "10.0.0.0/8"
  protocol     = "icmp"
  icmp_options = "8:0"
  action       = "accept"
  comment      = "Allow ICMP echo-request from internal VLANs"
  place_before = routeros_ip_firewall_filter.input_drop_all.id
}

resource "routeros_ip_firewall_filter" "input_drop_all" {
  chain   = "input"
  action  = "drop"
  log     = true
  comment = "Drop all other inbound to router"
}

# ─── FORWARD chain ────────────────────────────────────────────────────────────
# Single DROP rule — MikroTik does not route between any VLANs.
# All inter-VLAN routing is handled by VyOS.

resource "routeros_ip_firewall_filter" "fwd_drop_all" {
  chain   = "forward"
  action  = "drop"
  log     = true
  comment = "L2-only: drop all routed traffic (no inter-VLAN routing on MikroTik)"
}
