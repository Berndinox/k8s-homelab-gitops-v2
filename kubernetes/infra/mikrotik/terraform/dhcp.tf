# ── DHCP Server pro VLAN ──────────────────────────────────────────────────────
# NTP: Clients erhalten die Gateway-IP als NTP-Server.
# MikroTik selbst synct gegen BEV Wien (Stratum 1) — siehe interfaces.tf.

# DMZ — Services via BGP announced (10.0.10.200-254 reserved for LB-IPs)
resource "routeros_ip_pool" "dmz" {
  name    = "pool-dmz"
  ranges  = ["10.0.10.10-10.0.10.199"]
  comment = "DMZ pool (10.0.10.200/28 reserved for Cilium BGP LB-IPs)"
}

resource "routeros_ip_dhcp_server" "dmz" {
  name         = "dhcp-dmz"
  interface    = "${var.bridge_name}.${var.vlan_dmz}"
  address_pool = routeros_ip_pool.dmz.name
  lease_time   = var.dhcp_lease_time
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "dmz" {
  address    = var.subnet_dmz
  gateway    = "10.0.10.1"
  dns_server = ["10.0.10.1"]
  ntp_server = ["10.0.10.1"]
  comment    = "DMZ network"
}

# Server — Services via BGP announced (10.0.50.200-254 reserved for LB-IPs)
resource "routeros_ip_pool" "server" {
  name    = "pool-server"
  ranges  = ["10.0.50.10-10.0.50.199"]
  comment = "Server pool (10.0.50.200/28 reserved for Cilium BGP LB-IPs)"
}

resource "routeros_ip_dhcp_server" "server" {
  name         = "dhcp-server"
  interface    = "${var.bridge_name}.${var.vlan_server}"
  address_pool = routeros_ip_pool.server.name
  lease_time   = var.dhcp_lease_time
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "server" {
  address    = var.subnet_server
  gateway    = "10.0.50.1"
  dns_server = ["10.0.50.1"]
  ntp_server = ["10.0.50.1"]
  comment    = "Server network"
}

# WiFi Guest — isoliert, nur Internet
resource "routeros_ip_pool" "wifi" {
  name    = "pool-wifi"
  ranges  = ["10.0.30.10-10.0.30.254"]
  comment = "WiFi Guest pool"
}

resource "routeros_ip_dhcp_server" "wifi" {
  name         = "dhcp-wifi"
  interface    = "${var.bridge_name}.${var.vlan_wifi}"
  address_pool = routeros_ip_pool.wifi.name
  lease_time   = var.dhcp_lease_time
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "wifi" {
  address    = var.subnet_wifi
  gateway    = "10.0.30.1"
  dns_server = ["10.0.30.1"]
  ntp_server = ["10.0.30.1"]
  comment    = "WiFi Guest network"
}

# Client — Heimnetzgeräte, Internet + K8s Services
resource "routeros_ip_pool" "client" {
  name    = "pool-client"
  ranges  = ["10.0.40.10-10.0.40.254"]
  comment = "Client pool"
}

resource "routeros_ip_dhcp_server" "client" {
  name         = "dhcp-client"
  interface    = "${var.bridge_name}.${var.vlan_client}"
  address_pool = routeros_ip_pool.client.name
  lease_time   = var.dhcp_lease_time
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "client" {
  address    = var.subnet_client
  gateway    = "10.0.40.1"
  dns_server = ["10.0.40.1"]
  ntp_server = ["10.0.40.1"]
  comment    = "Client network"
}

# WiFi Secure — Trusted Devices
resource "routeros_ip_pool" "wifisec" {
  name    = "pool-wifisec"
  ranges  = ["10.0.60.10-10.0.60.254"]
  comment = "WiFi Secure pool"
}

resource "routeros_ip_dhcp_server" "wifisec" {
  name         = "dhcp-wifisec"
  interface    = "${var.bridge_name}.${var.vlan_wifisec}"
  address_pool = routeros_ip_pool.wifisec.name
  lease_time   = var.dhcp_lease_time
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "wifisec" {
  address    = var.subnet_wifisec
  gateway    = "10.0.60.1"
  dns_server = ["10.0.60.1"]
  ntp_server = ["10.0.60.1"]
  comment    = "WiFi Secure network"
}

# Cluster — Kubernetes nodes (static leases handled separately)
resource "routeros_ip_pool" "cluster" {
  name    = "pool-cluster"
  ranges  = ["10.0.100.20-10.0.100.99"]
  comment = "Cluster dynamic pool (nodes use static IPs)"
}

resource "routeros_ip_dhcp_server" "cluster" {
  name         = "dhcp-cluster"
  interface    = "${var.bridge_name}.${var.vlan_cluster}"
  address_pool = routeros_ip_pool.cluster.name
  lease_time   = "30m"
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "cluster" {
  address    = var.subnet_cluster
  gateway    = "10.0.100.1"
  dns_server = ["10.0.100.1"]
  ntp_server = ["10.0.100.1"]
  comment    = "Cluster network"
}

# MGMT — Management access
resource "routeros_ip_pool" "mgmt" {
  name    = "pool-mgmt"
  ranges  = ["10.0.200.20-10.0.200.254"]
  comment = "MGMT pool"
}

resource "routeros_ip_dhcp_server" "mgmt" {
  name         = "dhcp-mgmt"
  interface    = "${var.bridge_name}.${var.vlan_mgmt}"
  address_pool = routeros_ip_pool.mgmt.name
  lease_time   = "1h"
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "mgmt" {
  address    = var.subnet_mgmt
  gateway    = "10.0.200.1"
  dns_server = ["10.0.200.1"]
  ntp_server = ["10.0.200.1"]
  comment    = "MGMT network"
}
