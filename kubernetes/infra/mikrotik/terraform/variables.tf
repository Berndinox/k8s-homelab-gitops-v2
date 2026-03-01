variable "mikrotik_host" {
  description = "MikroTik management IP (VLAN 200)"
  type        = string
  default     = "10.0.200.1"
}

variable "mikrotik_user" {
  description = "MikroTik API username"
  type        = string
  sensitive   = true
}

variable "mikrotik_password" {
  description = "MikroTik API password"
  type        = string
  sensitive   = true
}

# ── VLAN IDs ──────────────────────────────────────────────────────────────────
variable "vlan_wan"     { default = 5 }
variable "vlan_dmz"     { default = 10 }
variable "vlan_wifi"    { default = 30 }
variable "vlan_server"  { default = 50 }
variable "vlan_wifisec" { default = 60 }
variable "vlan_cluster" { default = 100 }
variable "vlan_mgmt"    { default = 200 }

# ── Subnets ───────────────────────────────────────────────────────────────────
variable "subnet_dmz"     { default = "10.0.10.0/24" }
variable "subnet_wifi"    { default = "10.0.30.0/24" }
variable "subnet_server"  { default = "10.0.50.0/24" }
variable "subnet_wifisec" { default = "10.0.60.0/24" }
variable "subnet_cluster" { default = "10.0.100.0/24" }
variable "subnet_mgmt"    { default = "10.0.200.0/24" }

# ── Gateway IPs (MikroTik = .1 on each subnet) ───────────────────────────────
variable "gw_dmz"     { default = "10.0.10.1/24" }
variable "gw_wifi"    { default = "10.0.30.1/24" }
variable "gw_server"  { default = "10.0.50.1/24" }
variable "gw_wifisec" { default = "10.0.60.1/24" }
variable "gw_cluster" { default = "10.0.100.1/24" }
variable "gw_mgmt"    { default = "10.0.200.1/24" }

# ── Port assignments — VERIFY before applying! ────────────────────────────────
# CRS310-8G-2S+IN layout (from export.backup):
#   ether1     = WAN uplink to ISP modem (untagged VLAN 5)
#   ether2-7   = configurable access ports
#   ether8     = MGMT access port (untagged VLAN 200)
#   sfp-sfpplus1/2 = 10G trunk to Kubernetes nodes (tagged: VLAN 100,200)
#   bonding10 (bond22) = existing bond (check if still needed)
variable "port_wan"        { default = "ether1" }
variable "port_mgmt_access"{ default = "ether8" }
variable "port_trunk_1"    { default = "sfp-sfpplus1" }
variable "port_trunk_2"    { default = "sfp-sfpplus2" }
variable "bridge_name"     { default = "bridge" }

# ── BGP ───────────────────────────────────────────────────────────────────────
variable "bgp_local_as"  { default = 65000 }
variable "bgp_peer_as"   { default = 65100 }
variable "bgp_peers" {
  description = "Cilium node IPs on VLAN 100"
  default = [
    { name = "node-01", ip = "10.0.100.11" },
    { name = "node-02", ip = "10.0.100.12" },
    { name = "node-03", ip = "10.0.100.13" },
  ]
}

# ── DHCP ──────────────────────────────────────────────────────────────────────
variable "dhcp_lease_time" { default = "10m" }
