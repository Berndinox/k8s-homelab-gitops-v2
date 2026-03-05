# ── DHCP Server — VLAN 100 (Cluster) + VLAN 200 (MGMT) ──────────────────────
# Only these two VLANs retain DHCP on MikroTik for bootstrap independence.
# VLAN 10/30/40/50/60 DHCP will be handled by VyOS (next step).
#
# Note: Gateways are placeholders — will be updated to VyOS IPs after VyOS setup.

# ── Cluster VLAN 100 ──────────────────────────────────────────────────────────
resource "routeros_ip_pool" "cluster" {
  name    = "pool-cluster"
  ranges  = ["10.0.100.20-10.0.100.99"]
  comment = "Cluster dynamic pool (K8s nodes use static IPs)"
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
  gateway    = "10.0.100.1"          # Placeholder → will be VyOS IP on VLAN 100
  dns_server = ["10.0.100.1"]        # MikroTik for now (VyOS later)
  ntp_server = ["10.0.100.1"]        # MikroTik for now (VyOS later)
  comment    = "Cluster network — gateway TBD (VyOS)"
}

# ── MGMT VLAN 200 ─────────────────────────────────────────────────────────────
resource "routeros_ip_pool" "mgmt" {
  name    = "pool-mgmt"
  ranges  = ["10.0.200.21-10.0.200.253"]
  comment = "MGMT pool (.20 reserved for tf-runner Multus; .254 = MikroTik)"
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
  gateway    = "10.0.200.1"                    # Placeholder → will be VyOS IP on VLAN 200
  dns_server = ["10.0.200.2", "10.0.200.3"]   # DNS servers in MGMT VLAN (Pi-hole etc.)
  ntp_server = ["10.0.200.254"]                # MikroTik itself
  comment    = "MGMT network — gateway TBD (VyOS)"
}
