# ── Bridge (VLAN-aware) ───────────────────────────────────────────────────────
resource "routeros_interface_bridge" "main" {
  name           = var.bridge_name
  vlan_filtering = true
  comment        = "Main bridge — managed by Terraform"
}

# ── LACP Bond (bonding10) — sfp-sfpplus1+2 → L2 downstream switch → K8s nodes ─
resource "routeros_interface_bonding" "trunk_bond" {
  name         = var.bond_name
  slaves       = "${var.port_trunk_1},${var.port_trunk_2}"
  mode         = "802.3ad"
  lacp_rate    = "fast"
  mii_interval = "100ms"
  comment      = "LACP bond to downstream L2 switch (K8s nodes)"
}

# ── Bridge Ports ──────────────────────────────────────────────────────────────

# WAN uplink — untagged VLAN 5
resource "routeros_interface_bridge_port" "wan" {
  bridge      = routeros_interface_bridge.main.name
  interface   = var.port_wan
  pvid        = var.vlan_wan
  frame_types = "admit-only-untagged-and-priority-tagged"
  hw          = true
  comment     = "WAN uplink (ISP modem) — untagged VLAN ${var.vlan_wan}"
}

# MGMT access ports — ether2/3/4/5/8, alle untagged VLAN 200
resource "routeros_interface_bridge_port" "mgmt_access" {
  for_each    = toset(var.port_mgmt_ports)
  bridge      = routeros_interface_bridge.main.name
  interface   = each.value
  pvid        = var.vlan_mgmt
  frame_types = "admit-only-untagged-and-priority-tagged"
  hw          = true
  comment     = "MGMT access port — untagged VLAN ${var.vlan_mgmt}"
}

# WiFi Guest AP — access port untagged VLAN 30
resource "routeros_interface_bridge_port" "ap_wifi" {
  bridge      = routeros_interface_bridge.main.name
  interface   = var.port_ap_wifi
  pvid        = var.vlan_wifi
  frame_types = "admit-only-untagged-and-priority-tagged"
  hw          = true
  comment     = "WiFi Guest AP — untagged VLAN ${var.vlan_wifi}"
}

# WiFi Secure AP — access port untagged VLAN 60
resource "routeros_interface_bridge_port" "ap_wifisec" {
  bridge      = routeros_interface_bridge.main.name
  interface   = var.port_ap_wifisec
  pvid        = var.vlan_wifisec
  frame_types = "admit-only-untagged-and-priority-tagged"
  hw          = true
  comment     = "WiFi Secure AP — untagged VLAN ${var.vlan_wifisec}"
}

# LACP trunk bond — tagged, all K8s VLANs
resource "routeros_interface_bridge_port" "trunk_bond" {
  bridge      = routeros_interface_bridge.main.name
  interface   = routeros_interface_bonding.trunk_bond.name
  pvid        = 1
  frame_types = "admit-only-vlan-tagged"
  hw          = true
  comment     = "LACP trunk (bonding10) to K8s nodes via L2 switch"
  depends_on  = [routeros_interface_bonding.trunk_bond]
}

# ── Bridge VLAN Table ─────────────────────────────────────────────────────────

resource "routeros_interface_bridge_vlan" "wan" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_wan]
  tagged   = [var.bridge_name]
  comment  = "WAN — bridge CPU only (WAN port untagged via pvid)"
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

resource "routeros_interface_bridge_vlan" "dmz" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_dmz]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  comment    = "DMZ VLAN ${var.vlan_dmz} — bond trunk + bridge CPU"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "server" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_server]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  comment    = "Server VLAN ${var.vlan_server} — bond trunk + bridge CPU"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "client" {
  bridge     = routeros_interface_bridge.main.name
  vlan_ids   = [var.vlan_client]
  tagged     = [var.bridge_name, routeros_interface_bonding.trunk_bond.name]
  comment    = "Client VLAN ${var.vlan_client} — bond trunk + bridge CPU"
  depends_on = [routeros_interface_bonding.trunk_bond]
}

resource "routeros_interface_bridge_vlan" "wifi" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_wifi]
  tagged   = [var.bridge_name]
  untagged = [var.port_ap_wifi]
  comment  = "WiFi Guest VLAN ${var.vlan_wifi} — ether6 access, bridge CPU for routing"
}

resource "routeros_interface_bridge_vlan" "wifisec" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_wifisec]
  tagged   = [var.bridge_name]
  untagged = [var.port_ap_wifisec]
  comment  = "WiFi Secure VLAN ${var.vlan_wifisec} — ether7 access, bridge CPU for routing"
}

# ── IP Addresses on Bridge VLAN Interfaces ───────────────────────────────────

resource "routeros_ip_address" "dmz_gw" {
  address    = var.gw_dmz
  interface  = "${var.bridge_name}.${var.vlan_dmz}"
  comment    = "DMZ gateway"
  depends_on = [routeros_interface_bridge_vlan.dmz]
}

resource "routeros_ip_address" "server_gw" {
  address    = var.gw_server
  interface  = "${var.bridge_name}.${var.vlan_server}"
  comment    = "Server gateway"
  depends_on = [routeros_interface_bridge_vlan.server]
}

resource "routeros_ip_address" "client_gw" {
  address    = var.gw_client
  interface  = "${var.bridge_name}.${var.vlan_client}"
  comment    = "Client gateway"
  depends_on = [routeros_interface_bridge_vlan.client]
}

resource "routeros_ip_address" "cluster_gw" {
  address    = var.gw_cluster
  interface  = "${var.bridge_name}.${var.vlan_cluster}"
  comment    = "Cluster gateway"
  depends_on = [routeros_interface_bridge_vlan.cluster]
}

resource "routeros_ip_address" "mgmt_gw" {
  address    = var.gw_mgmt
  interface  = "${var.bridge_name}.${var.vlan_mgmt}"
  comment    = "MGMT gateway"
  depends_on = [routeros_interface_bridge_vlan.mgmt]
}

resource "routeros_ip_address" "wifi_gw" {
  address    = var.gw_wifi
  interface  = "${var.bridge_name}.${var.vlan_wifi}"
  comment    = "WiFi Guest gateway"
  depends_on = [routeros_interface_bridge_vlan.wifi]
}

resource "routeros_ip_address" "wifisec_gw" {
  address    = var.gw_wifisec
  interface  = "${var.bridge_name}.${var.vlan_wifisec}"
  comment    = "WiFi Secure gateway"
  depends_on = [routeros_interface_bridge_vlan.wifisec]
}

# Default Route → VyOS (10.0.50.2) on Server VLAN
# VyOS VM handles WAN (VLAN 5), NAT, Stateful FW, IDS, VPN.
# MikroTik does L3 inter-VLAN routing only (ASIC wire-speed).
resource "routeros_ip_route" "default_via_vyos" {
  dst_address = "0.0.0.0/0"
  gateway     = "10.0.50.2"
  comment     = "Default route via VyOS on Server VLAN"
  depends_on  = [routeros_ip_address.server_gw]
}

# DNS — MikroTik als lokaler Resolver (Upstream: Quad9)
# Clients erhalten Gateway-IP via DHCP → fragen MikroTik → MikroTik fragt Quad9.
# Für AdGuard Home: servers hier auf AdGuard-IP umstellen (kein DHCP-Änderung nötig).
resource "routeros_ip_dns" "main" {
  servers               = ["9.9.9.9", "149.112.112.112"]
  allow_remote_requests = true
}

# NTP Client — BEV Wien (Stratum 1, österreichische Atomuhr, NTS)
resource "routeros_system_ntp_client" "main" {
  enabled = true
  mode    = "unicast"
  servers = var.ntp_servers
}
