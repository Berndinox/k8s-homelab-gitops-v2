# ── Bridge (VLAN-aware, L2 only) ──────────────────────────────────────────────
# CRS310 / 98DX226S: pure L2 switching in ASIC.
# All routing delegated to VyOS KubeVirt VM.
resource "routeros_interface_bridge" "main" {
  name           = var.bridge_name
  vlan_filtering = true
  auto_mac       = false
  admin_mac      = "F4:1E:57:2B:BC:7E" # Stable bridge MAC — prevents MAC flap on port-up
  comment        = "Main bridge — L2 only, managed by Terraform"
}

# ── LACP Bond — sfp-sfpplus1+2 → L2 downstream switch → K8s nodes ────────────
resource "routeros_interface_bonding" "trunk_bond" {
  name         = var.bond_name
  slaves       = "${var.port_trunk_1},${var.port_trunk_2}"
  mode         = "802.3ad"
  lacp_rate    = "fast"
  mii_interval = "100ms"
  comment      = "LACP bond to downstream L2 switch (K8s nodes)"
}

# ── Bridge Ports ──────────────────────────────────────────────────────────────
# hw = true:              ASIC L2 forwarding (no CPU involvement for switching)
# ingress_filtering = true: ASIC drops frames arriving on wrong VLAN at ingress

# WAN uplink — untagged VLAN 5
resource "routeros_interface_bridge_port" "wan" {
  bridge            = routeros_interface_bridge.main.name
  interface         = var.port_wan
  pvid              = var.vlan_wan
  frame_types       = "admit-only-untagged-and-priority-tagged"
  hw                = true
  ingress_filtering = true
  comment           = "WAN uplink (ISP modem) — untagged VLAN ${var.vlan_wan}"
}

# MGMT access ports — ether2/3/4/5/8, untagged VLAN 200
resource "routeros_interface_bridge_port" "mgmt_access" {
  for_each          = toset(var.port_mgmt_ports)
  bridge            = routeros_interface_bridge.main.name
  interface         = each.value
  pvid              = var.vlan_mgmt
  frame_types       = "admit-only-untagged-and-priority-tagged"
  hw                = true
  ingress_filtering = true
  comment           = "MGMT access port — untagged VLAN ${var.vlan_mgmt}"
}

# WiFi Guest AP — access port untagged VLAN 30
resource "routeros_interface_bridge_port" "ap_wifi" {
  bridge            = routeros_interface_bridge.main.name
  interface         = var.port_ap_wifi
  pvid              = var.vlan_wifi
  frame_types       = "admit-only-untagged-and-priority-tagged"
  hw                = true
  ingress_filtering = true
  comment           = "WiFi Guest AP — untagged VLAN ${var.vlan_wifi}"
}

# WiFi Secure AP — access port untagged VLAN 60
resource "routeros_interface_bridge_port" "ap_wifisec" {
  bridge            = routeros_interface_bridge.main.name
  interface         = var.port_ap_wifisec
  pvid              = var.vlan_wifisec
  frame_types       = "admit-only-untagged-and-priority-tagged"
  hw                = true
  ingress_filtering = true
  comment           = "WiFi Secure AP — untagged VLAN ${var.vlan_wifisec}"
}

# LACP trunk bond — tagged, all VLANs
resource "routeros_interface_bridge_port" "trunk_bond" {
  bridge            = routeros_interface_bridge.main.name
  interface         = routeros_interface_bonding.trunk_bond.name
  pvid              = 1
  frame_types       = "admit-only-vlan-tagged"
  hw                = true
  ingress_filtering = true
  comment           = "LACP trunk (bonding1) to K8s nodes via L2 switch"
  depends_on        = [routeros_interface_bonding.trunk_bond]
}

# ── Bridge VLAN Table ─────────────────────────────────────────────────────────
# Defines which VLANs are forwarded on which ports. L2 only — no routing.

resource "routeros_interface_bridge_vlan" "wan" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_wan]
  tagged   = [var.bridge_name]
  comment  = "WAN VLAN ${var.vlan_wan} — bridge CPU only (ether1 untagged via pvid)"
}

resource "routeros_interface_bridge_vlan" "dmz" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_dmz]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  comment    = "DMZ VLAN ${var.vlan_dmz} — bond trunk + bridge CPU"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "wifi" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_wifi]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  untagged   = [var.port_ap_wifi]
  comment    = "WiFi Guest VLAN ${var.vlan_wifi} — ether6 access, bond trunk"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "client" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_client]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  comment    = "Client VLAN ${var.vlan_client} — bond trunk + bridge CPU"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "server" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_server]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  comment    = "Server VLAN ${var.vlan_server} — bond trunk + bridge CPU"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "wifisec" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_wifisec]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  untagged   = [var.port_ap_wifisec]
  comment    = "WiFi Secure VLAN ${var.vlan_wifisec} — ether7 access, bond trunk"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "cluster" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_cluster]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  comment    = "Cluster VLAN ${var.vlan_cluster} — bond trunk + bridge CPU"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "mgmt" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_mgmt]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  untagged   = var.port_mgmt_ports
  comment    = "MGMT VLAN ${var.vlan_mgmt} — bond trunk + bridge CPU; ether2-5+8 untagged access"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

# ── MikroTik Management IPs ───────────────────────────────────────────────────
# Only VLAN 100 and 200 have IPs — for DHCP/DNS/NTP service only, not routing.
# Gateways for all VLANs will be VyOS (configured in next step).

resource "routeros_ip_address" "cluster_gw" {
  address    = var.gw_cluster
  interface  = "${var.bridge_name}.${var.vlan_cluster}"
  comment    = "MikroTik DHCP/DNS/NTP on Cluster VLAN — not a gateway"
  depends_on = [routeros_interface_bridge_vlan.cluster]
}

resource "routeros_ip_address" "mgmt_gw" {
  address    = var.gw_mgmt
  interface  = "${var.bridge_name}.${var.vlan_mgmt}"
  comment    = "MikroTik management IP on MGMT VLAN"
  depends_on = [routeros_interface_bridge_vlan.mgmt]
}

# ── DNS — MikroTik as local resolver (Upstream: Quad9) ───────────────────────
# VLAN 100/200 clients use MikroTik IP as DNS (via DHCP).
# For AdGuard/Pi-hole: update servers to internal IP, no DHCP change needed.
resource "routeros_ip_dns" "main" {
  servers               = ["9.9.9.9", "149.112.112.112"]
  allow_remote_requests = true
}

# ── NTP Client — BEV Wien (Stratum 1, NTS) ───────────────────────────────────
resource "routeros_system_ntp_client" "main" {
  enabled = true
  mode    = "unicast"
  servers = var.ntp_servers
}
