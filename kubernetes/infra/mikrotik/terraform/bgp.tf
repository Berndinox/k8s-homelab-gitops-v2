# ── BGP — MikroTik (AS 65000) ↔ Cilium (AS 65100) + VyOS (AS 65200) ─────────
#
# MikroTik AS 65000 peers with:
#   - Each Cilium node on VLAN 100 (learns Pod CIDRs + LB Service IPs)
#   - VyOS on VLAN 50 (redistributes Cilium routes → no double-NAT)
#
# Flow:  Cilium → MikroTik → VyOS
#        Pod CIDRs + LB IPs propagated so VyOS knows return routes.
#        VyOS only NATs at WAN, not for pod traffic.
#
# After applying:
#   /routing/bgp/session print         — check session state
#   /ip/route print where bgp          — verify pod routes received

# ── Cilium Peers (VLAN 100) ─────────────────────────────────────────────────

resource "routeros_routing_bgp_connection" "cilium" {
  for_each = { for peer in var.bgp_peers : peer.name => peer }

  name           = "cilium-${each.value.name}"
  as             = var.bgp_local_as
  router_id      = var.bgp_router_id
  remote_as      = var.bgp_peer_as
  remote_address = each.value.ip

  address_families = "ip"

  input {
    filter = "accept-private"
  }

  output {
    filter = "reject-all"
  }

  comment = "Cilium BGP peer — ${each.value.name} (${each.value.ip})"
}

# ── VyOS Peer (VLAN 50) ─────────────────────────────────────────────────────
# VyOS learns Pod CIDRs + LB IPs → can route return traffic without NAT.
# VyOS advertises nothing to MikroTik (MikroTik has its own default route).

resource "routeros_routing_bgp_connection" "vyos" {
  name           = "vyos"
  as             = var.bgp_local_as
  router_id      = var.bgp_router_id
  remote_as      = var.bgp_vyos_as
  remote_address = "10.0.50.2"

  address_families = "ip"

  input {
    filter = "reject-all"
  }

  output {
    filter = "advertise-cilium-routes"
  }

  comment = "VyOS BGP peer — redistribute Cilium pod/service routes"
}

# ── Routing Filters ───────────────────────────────────────────────────────────

# accept-private: nur RFC1918-Routen akzeptieren (Pod-CIDRs, LB-IPs)
# Verhindert dass eine versehentlich advertised Default-Route (0.0.0.0/0)
# die WAN-Route überschreibt.
resource "routeros_routing_filter_rule" "accept_private" {
  chain = "accept-private"
  rule  = "if (dst in 10.0.0.0/8) { accept }"
}

resource "routeros_routing_filter_rule" "accept_private_reject" {
  chain = "accept-private"
  rule  = "if (dst in 0.0.0.0/0) { reject }"
}

resource "routeros_routing_filter_rule" "reject_all" {
  chain = "reject-all"
  rule  = "if (dst in 0.0.0.0/0) { reject }"
}

# advertise-cilium-routes: Forward BGP-learned RFC1918 routes to VyOS.
# Matches routes learned from Cilium peers (Pod CIDRs + LB Service IPs).
# Only private ranges — never leak a default route to VyOS.
resource "routeros_routing_filter_rule" "advertise_cilium_accept" {
  chain = "advertise-cilium-routes"
  rule  = "if (dst in 10.0.0.0/8 && protocol bgp) { accept }"
}

resource "routeros_routing_filter_rule" "advertise_cilium_reject" {
  chain = "advertise-cilium-routes"
  rule  = "if (dst in 0.0.0.0/0) { reject }"
}
