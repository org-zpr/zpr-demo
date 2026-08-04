#!/usr/bin/env bash
# One-time zpr-core setup after `tofu apply`. Discovers the egress adapter's dynamic
# ZPR address and installs the egress return-path routing. Does NOT start the devices
# — run ./start-device-a.sh and ./start-device-b.sh for that.
#
# Rerun after any stop/start of zpr-core (restarted adapters get a NEW egress addr).
source "$(dirname "$0")/lib.sh"

# --- egress address (what devices publish to) ---
echo "Discovering egress ZPR address on zpr-core ($ZPR_CORE_IP)..."
EGRESS_ADDR=$(egress_addr)
echo "  egress-addr = $EGRESS_ADDR"

# --- egress return-path routing (fixes the overlapping-/32 blocker) ---
# On zpr-core, node(tun9), vs-adapter(tun8) and the egress adapter's tun ALL carry
# fd5a:5052::/32, so the kernel sends egress's replies (e.g. the MQTT SYN-ACK) out
# the node's tun instead of the egress adapter's — devices' TCP handshakes never
# complete. Source-based policy routing forces traffic FROM the egress addr out the
# egress tun. (The laptop avoids this by running egress in a container netns.)
echo "Configuring egress return-path routing on zpr-core..."
EGRESS_TUN=$(ssh_core "ip -o -6 addr show | grep '$EGRESS_ADDR' | awk '{print \$2}' | head -1")
[ -n "$EGRESS_TUN" ] || { echo "ERROR: could not find egress tun for $EGRESS_ADDR" >&2; exit 1; }
# Idempotent: drop any stale rules pointing at table 100 (from a previous run with a
# different egress addr), then install the current one. Only egress uses table 100.
ssh_core "sudo bash -c 'while ip -6 rule show | grep -q \"lookup 100\"; do ip -6 rule del lookup 100; done'"
ssh_core "sudo ip -6 rule add from $EGRESS_ADDR lookup 100"
ssh_core "sudo ip -6 route replace $ZPR_PREFIX dev $EGRESS_TUN table 100"
echo "  egress tun = $EGRESS_TUN; traffic from $EGRESS_ADDR -> table 100 -> $EGRESS_TUN"

echo
echo "zpr-core ready. Now start the devices:"
echo "  ./start-device-a.sh    # allowed -> telemetry flows to OCI"
echo "  ./start-device-b.sh    # blocked -> denied by the visa service"
