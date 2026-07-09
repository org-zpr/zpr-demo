#!/usr/bin/env bash
# Shared helpers for the OCI ZPR demo scripts. SOURCED by post-init.sh,
# start-device-a.sh, start-device-b.sh — not executed directly.
#
# ZPR grants dynamic addresses to the ingress/ingress2/egress adapters at runtime,
# so they can't be known before the adapters connect; these helpers discover them
# from the adapters' journals over SSH.
set -euo pipefail

# Guard against running this directly (it only defines vars/functions).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "lib.sh is a sourced library; run post-init.sh / start-device-a.sh / start-device-b.sh" >&2
  exit 1
fi

KEY="${SSH_KEY:-$HOME/.ssh/zpr-demo}"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # this dir = the tofu root
ZPR_DIR="${ZPR_DIR:-/opt/zpr}"
BROKER_PORT="${BROKER_PORT:-1883}"
ZPR_PREFIX="${ZPR_PREFIX:-fd5a:5052::/32}"               # the ZPR address space

# --- instance IPs from tofu outputs ---
DEVICE_A_IP=$(tofu -chdir="$TF_DIR" output -raw device_a_public_ip)
DEVICE_B_IP=$(tofu -chdir="$TF_DIR" output -raw device_b_public_ip)
ZPR_CORE_IP=$(tofu -chdir="$TF_DIR" output -raw zpr_core_public_ip)

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
ssh_core() { ssh "${SSH_OPTS[@]}" "opc@$ZPR_CORE_IP" "$@"; }
ssh_devA() { ssh "${SSH_OPTS[@]}" "opc@$DEVICE_A_IP" "$@"; }
ssh_devB() { ssh "${SSH_OPTS[@]}" "opc@$DEVICE_B_IP" "$@"; }

# Pattern in adapter logs: "Link N granted ZPR addresses [IpAddress(V6: <addr>)]"
GRANT_RE='granted ZPR addresses \[IpAddress\(V6: \K[0-9a-f:]+'

# discover_addr <ssh_fn> <unit> : poll the journal until the granted address appears.
# Scoped to the unit's CURRENT systemd invocation so a stale address from an earlier
# run (e.g. before a restart) is never picked up.
discover_addr() {
  local fn="$1" unit="$2" addr="" iid i
  iid=$($fn "systemctl show -p InvocationID --value $unit 2>/dev/null" || true)
  for i in $(seq 1 30); do
    addr=$($fn "sudo journalctl -u $unit ${iid:+_SYSTEMD_INVOCATION_ID=$iid} --no-pager 2>/dev/null | grep -oP '$GRANT_RE' | tail -1" || true)
    [ -n "$addr" ] && { printf '%s' "$addr"; return 0; }
    sleep 5
  done
  echo "ERROR: no ZPR address from $unit after ~150s" >&2
  return 1
}

# tun_name <ssh_fn> : the (single) dynamic TUN the adapter created
tun_name() { "$1" "ip -o link show type tun | awk -F': ' 'NR==1{print \$2}'"; }

# egress_addr : the egress adapter's current ZPR address (the broker the devices reach)
egress_addr() { discover_addr ssh_core zpr-egress; }

# start_device <ssh_fn> <adapter-unit> <label> : discover the device's ingress addr,
# route broker traffic out its TUN, write device.env, and start the publisher unit.
# Self-contained: re-discovers the egress addr each call. Requires post-init.sh to
# have installed the egress return-path routing on zpr-core first.
start_device() {
  local fn="$1" unit="$2" label="$3" egress ingress tun
  egress=$(egress_addr)
  # The adapter is installed-but-stopped at boot (see device cloud-init), so this is
  # its first start — and it's against a zpr-core that post-init already confirmed is
  # up, so the handshake completes cleanly with no race. `restart` also makes re-runs
  # idempotent (a running adapter just reconnects). discover_addr is invocation-scoped.
  echo "[$label] starting $unit against the ready ZPR core..."
  $fn "sudo systemctl restart $unit"
  ingress=$(discover_addr "$fn" "$unit")
  tun=$(tun_name "$fn")
  echo "[$label] broker=$egress bind=$ingress tun=$tun"

  $fn "sudo ip -6 route replace $egress dev $tun"
  $fn "sudo tee $ZPR_DIR/devices/device.env >/dev/null <<EOF
MQTT_BROKER_HOST=$egress
MQTT_BROKER_PORT=$BROKER_PORT
BIND_ADDRESS=$ingress
EOF"
  $fn "sudo systemctl restart zpr-device.service"
  echo "[$label] publisher started (systemctl status zpr-device to check)."
}
