# ── BGP — MikroTik (AS 65000) ↔ Cilium (AS 65100) ───────────────────────────
#
# MikroTik AS 65000 peers with each Cilium node individually.
# Cilium advertises: Pod CIDRs + LoadBalancer Service IPs.
# MikroTik advertises: nothing (Cilium only needs routes INTO the cluster).
#
# After applying:
#   /routing/bgp/session print         — check session state
#   /ip/route print where bgp          — verify pod routes received

resource "routeros_routing_bgp_connection" "cilium" {
  for_each = { for peer in var.bgp_peers : peer.name => peer }

  name        = "cilium-${each.value.name}"
  as          = var.bgp_local_as
  remote_as   = var.bgp_peer_as
  remote_address = each.value.ip

  address_families = "ip"

  input {
    filter = "accept-all"
  }

  output {
    filter = "reject-all" # MikroTik advertises nothing to Cilium
  }

  comment = "Cilium BGP peer — ${each.value.name} (${each.value.ip})"
}

# ── Routing Filters ───────────────────────────────────────────────────────────

resource "routeros_routing_filter_rule" "accept_all" {
  chain  = "accept-all"
  rule   = "if (dst in 0.0.0.0/0) { accept }"
}

resource "routeros_routing_filter_rule" "reject_all" {
  chain  = "reject-all"
  rule   = "if (dst in 0.0.0.0/0) { reject }"
}
