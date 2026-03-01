# ── Bridge (VLAN-aware) ───────────────────────────────────────────────────────
resource "routeros_interface_bridge" "main" {
  name           = var.bridge_name
  vlan_filtering = true
  comment        = "Main bridge — managed by Terraform"
}

# ── Bridge Ports ──────────────────────────────────────────────────────────────

# WAN uplink — untagged VLAN 5, no other VLANs
resource "routeros_interface_bridge_port" "wan" {
  bridge      = routeros_interface_bridge.main.name
  interface   = var.port_wan
  pvid        = var.vlan_wan
  frame_types = "admit-only-untagged-and-priority-tagged"
  comment     = "WAN uplink (ISP modem) — untagged VLAN ${var.vlan_wan}"
}

# MGMT access port — untagged VLAN 200, for direct admin access
resource "routeros_interface_bridge_port" "mgmt_access" {
  bridge      = routeros_interface_bridge.main.name
  interface   = var.port_mgmt_access
  pvid        = var.vlan_mgmt
  frame_types = "admit-only-untagged-and-priority-tagged"
  comment     = "MGMT access port — untagged VLAN ${var.vlan_mgmt}"
}

# 10G Trunk to Kubernetes nodes — tagged VLANs 100+200
resource "routeros_interface_bridge_port" "trunk1" {
  bridge      = routeros_interface_bridge.main.name
  interface   = var.port_trunk_1
  pvid        = 1
  frame_types = "admit-only-vlan-tagged"
  comment     = "10G trunk to K8s nodes (VLAN 100, 200)"
}

resource "routeros_interface_bridge_port" "trunk2" {
  bridge      = routeros_interface_bridge.main.name
  interface   = var.port_trunk_2
  pvid        = 1
  frame_types = "admit-only-vlan-tagged"
  comment     = "10G trunk to K8s nodes (VLAN 100, 200)"
}

# ── Bridge VLAN Table ─────────────────────────────────────────────────────────
# Each entry defines which ports carry which VLANs (tagged/untagged)

resource "routeros_interface_bridge_vlan" "wan" {
  bridge  = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_wan]
  # Tagged on bridge CPU port only (for routing)
  tagged  = [var.bridge_name]
  comment = "WAN — WAN port is untagged (pvid), bridge CPU tagged for routing"
}

resource "routeros_interface_bridge_vlan" "cluster" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_cluster]
  tagged   = [var.bridge_name, var.port_trunk_1, var.port_trunk_2]
  comment  = "Cluster VLAN ${var.vlan_cluster} — 10G trunks + bridge CPU"
}

resource "routeros_interface_bridge_vlan" "mgmt" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_mgmt]
  tagged   = [var.bridge_name, var.port_trunk_1, var.port_trunk_2]
  comment  = "MGMT VLAN ${var.vlan_mgmt} — trunks + bridge CPU (mgmt port is untagged/pvid)"
}

resource "routeros_interface_bridge_vlan" "dmz" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_dmz]
  tagged   = [var.bridge_name, var.port_trunk_1, var.port_trunk_2]
  comment  = "DMZ VLAN ${var.vlan_dmz} — 10G trunks + bridge CPU"
}

resource "routeros_interface_bridge_vlan" "server" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_server]
  tagged   = [var.bridge_name, var.port_trunk_1, var.port_trunk_2]
  comment  = "Server VLAN ${var.vlan_server} — 10G trunks + bridge CPU"
}

resource "routeros_interface_bridge_vlan" "wifi" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_wifi]
  tagged   = [var.bridge_name]
  comment  = "WiFi Guest VLAN ${var.vlan_wifi} — bridge CPU only (AP tags it)"
}

resource "routeros_interface_bridge_vlan" "wifisec" {
  bridge   = routeros_interface_bridge.main.name
  vlan_ids = [var.vlan_wifisec]
  tagged   = [var.bridge_name]
  comment  = "WiFi Secure VLAN ${var.vlan_wifisec} — bridge CPU only (AP tags it)"
}

# ── IP Addresses on Bridge VLAN Interfaces ───────────────────────────────────
# MikroTik creates virtual VLAN interfaces as "bridge.VLANID"

resource "routeros_ip_address" "dmz_gw" {
  address   = var.gw_dmz
  interface = "${var.bridge_name}.${var.vlan_dmz}"
  comment   = "DMZ gateway"
  depends_on = [routeros_interface_bridge_vlan.dmz]
}

resource "routeros_ip_address" "server_gw" {
  address   = var.gw_server
  interface = "${var.bridge_name}.${var.vlan_server}"
  comment   = "Server gateway"
  depends_on = [routeros_interface_bridge_vlan.server]
}

resource "routeros_ip_address" "cluster_gw" {
  address   = var.gw_cluster
  interface = "${var.bridge_name}.${var.vlan_cluster}"
  comment   = "Cluster gateway"
  depends_on = [routeros_interface_bridge_vlan.cluster]
}

resource "routeros_ip_address" "mgmt_gw" {
  address   = var.gw_mgmt
  interface = "${var.bridge_name}.${var.vlan_mgmt}"
  comment   = "MGMT gateway"
  depends_on = [routeros_interface_bridge_vlan.mgmt]
}

resource "routeros_ip_address" "wifi_gw" {
  address   = var.gw_wifi
  interface = "${var.bridge_name}.${var.vlan_wifi}"
  comment   = "WiFi Guest gateway"
  depends_on = [routeros_interface_bridge_vlan.wifi]
}

resource "routeros_ip_address" "wifisec_gw" {
  address   = var.gw_wifisec
  interface = "${var.bridge_name}.${var.vlan_wifisec}"
  comment   = "WiFi Secure gateway"
  depends_on = [routeros_interface_bridge_vlan.wifisec]
}

# WAN — DHCP client on bridge.5
resource "routeros_ip_dhcp_client" "wan" {
  interface  = "${var.bridge_name}.${var.vlan_wan}"
  add_default_route = true
  use_peer_dns      = false
  comment    = "WAN DHCP from ISP"
  depends_on = [routeros_interface_bridge_vlan.wan]
}

# DNS
resource "routeros_ip_dns" "main" {
  servers          = ["1.1.1.1", "8.8.8.8"]
  allow_remote_requests = true
}
