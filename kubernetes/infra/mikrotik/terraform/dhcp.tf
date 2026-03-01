# ── DHCP Server pro VLAN ──────────────────────────────────────────────────────

# WiFi Guest — isoliert, nur Internet
resource "routeros_ip_pool" "wifi" {
  name    = "pool-wifi"
  ranges  = ["10.0.30.10-10.0.30.254"]
  comment = "WiFi Guest pool"
}

resource "routeros_ip_dhcp_server" "wifi" {
  name       = "dhcp-wifi"
  interface  = "${var.bridge_name}.${var.vlan_wifi}"
  address_pool = routeros_ip_pool.wifi.name
  lease_time = var.dhcp_lease_time
  disabled   = false
}

resource "routeros_ip_dhcp_server_network" "wifi" {
  address    = var.subnet_wifi
  gateway    = "10.0.30.1"
  dns_server = ["10.0.30.1"]
  comment    = "WiFi Guest network"
}

# WiFi Secure — Trusted Devices
resource "routeros_ip_pool" "wifisec" {
  name    = "pool-wifisec"
  ranges  = ["10.0.60.10-10.0.60.254"]
  comment = "WiFi Secure pool"
}

resource "routeros_ip_dhcp_server" "wifisec" {
  name       = "dhcp-wifisec"
  interface  = "${var.bridge_name}.${var.vlan_wifisec}"
  address_pool = routeros_ip_pool.wifisec.name
  lease_time = var.dhcp_lease_time
  disabled   = false
}

resource "routeros_ip_dhcp_server_network" "wifisec" {
  address    = var.subnet_wifisec
  gateway    = "10.0.60.1"
  dns_server = ["10.0.60.1"]
  comment    = "WiFi Secure network"
}

# Cluster — Kubernetes nodes (static leases handled separately)
resource "routeros_ip_pool" "cluster" {
  name    = "pool-cluster"
  ranges  = ["10.0.100.20-10.0.100.99"]
  comment = "Cluster dynamic pool (nodes use static)"
}

resource "routeros_ip_dhcp_server" "cluster" {
  name       = "dhcp-cluster"
  interface  = "${var.bridge_name}.${var.vlan_cluster}"
  address_pool = routeros_ip_pool.cluster.name
  lease_time = "30m"
  disabled   = false
}

resource "routeros_ip_dhcp_server_network" "cluster" {
  address    = var.subnet_cluster
  gateway    = "10.0.100.1"
  dns_server = ["10.0.100.1"]
  comment    = "Cluster network"
}

# MGMT — Management access
resource "routeros_ip_pool" "mgmt" {
  name    = "pool-mgmt"
  ranges  = ["10.0.200.20-10.0.200.254"]
  comment = "MGMT pool"
}

resource "routeros_ip_dhcp_server" "mgmt" {
  name       = "dhcp-mgmt"
  interface  = "${var.bridge_name}.${var.vlan_mgmt}"
  address_pool = routeros_ip_pool.mgmt.name
  lease_time = "1h"
  disabled   = false
}

resource "routeros_ip_dhcp_server_network" "mgmt" {
  address    = var.subnet_mgmt
  gateway    = "10.0.200.1"
  dns_server = ["10.0.200.1"]
  comment    = "MGMT network"
}
