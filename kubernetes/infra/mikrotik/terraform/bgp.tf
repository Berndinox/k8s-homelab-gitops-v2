# ── BGP — MikroTik (AS 65000) ↔ Cilium (AS 65100) ──────────────────────────
#
# MikroTik peers with each Cilium node on VLAN 100.
# Learns Pod CIDRs + LB Service IPs → routes them to internal VLANs.
# VyOS uses static route (10.0.0.0/8 → MikroTik) — no BGP needed.
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
