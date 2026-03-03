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
variable "vlan_client"  { default = 40 }
variable "vlan_server"  { default = 50 }
variable "vlan_wifisec" { default = 60 }
variable "vlan_cluster" { default = 100 }
variable "vlan_mgmt"    { default = 200 }

# ── Subnets ───────────────────────────────────────────────────────────────────
variable "subnet_dmz"     { default = "10.0.10.0/24" }
variable "subnet_wifi"    { default = "10.0.30.0/24" }
variable "subnet_client"  { default = "10.0.40.0/24" }
variable "subnet_server"  { default = "10.0.50.0/24" }
variable "subnet_wifisec" { default = "10.0.60.0/24" }
variable "subnet_cluster" { default = "10.0.100.0/24" }
variable "subnet_mgmt"    { default = "10.0.200.0/24" }

# ── Gateway IPs (MikroTik = .1 on each subnet) ───────────────────────────────
variable "gw_dmz"     { default = "10.0.10.1/24" }
variable "gw_wifi"    { default = "10.0.30.1/24" }
variable "gw_client"  { default = "10.0.40.1/24" }
variable "gw_server"  { default = "10.0.50.1/24" }
variable "gw_wifisec" { default = "10.0.60.1/24" }
variable "gw_cluster" { default = "10.0.100.1/24" }
variable "gw_mgmt"    { default = "10.0.200.1/24" }

# ── Port assignments ──────────────────────────────────────────────────────────
# CRS310-8G-2S+IN layout:
#   ether1       = WAN uplink to ISP modem (untagged VLAN 5)
#   ether2-5     = MGMT access ports (untagged VLAN 200) — multiple management devices
#   ether6       = WiFi Guest AP access port (untagged VLAN 30)
#   ether7       = WiFi Secure AP access port (untagged VLAN 60)
#   ether8       = MGMT access port (untagged VLAN 200)
#   sfp-sfpplus1 = LACP bond slave → bonding1 → L2 downstream switch → K8s nodes
#   sfp-sfpplus2 = LACP bond slave → bonding1
variable "port_wan"         { default = "ether1" }
variable "port_mgmt_ports"  { default = ["ether2", "ether3", "ether4", "ether5", "ether8"] }
variable "port_ap_wifi"     { default = "ether6" }
variable "port_ap_wifisec"  { default = "ether7" }
variable "port_trunk_1"     { default = "sfp-sfpplus1" }
variable "port_trunk_2"     { default = "sfp-sfpplus2" }
variable "bond_name"        { default = "bonding1" }
variable "bridge_name"      { default = "bridge" }

# ── BGP ───────────────────────────────────────────────────────────────────────
variable "bgp_local_as"  { default = 65000 }
variable "bgp_peer_as"   { default = 65100 }
variable "bgp_vyos_as"   { default = 65200 }
variable "bgp_router_id" { default = "10.0.200.1" }
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

# ── NTP ───────────────────────────────────────────────────────────────────────
# BEV (Bundesamt für Eich- und Vermessungswesen) — Vienna, Stratum 1, NTS
variable "ntp_servers" {
  default = ["bevtime1.metrologie.at", "bevtime2.metrologie.at"]
}
