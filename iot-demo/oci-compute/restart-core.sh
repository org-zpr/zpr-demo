#!/usr/bin/env bash
# Restart zpr-core's ZPR chain SEQUENTIALLY (node -> VS adapter -> visa service ->
# egress), with pauses so each unit is ready before the next starts. Use after
# swapping the ph/vs binary on a live instance, or any time the chain needs a clean
# bounce.
#
# Why not just `systemctl restart node vs-adapter vs egress`? A batched restart
# re-triggers the AA-registration race: the units' ExecStartPre readiness gates grep
# the journal for markers (becoming ACTIVE / registered VSS) that are STALE from the
# previous run, so they pass instantly and don't enforce ordering. Those gates only
# work on a fresh boot (clean journal). This script enforces the order with pauses.
#
# After this, rerun ./post-init.sh + ./start-device-a.sh + ./start-device-b.sh — the
# adapters get new dynamic ZPR addresses on restart.
source "$(dirname "$0")/lib.sh"

echo "Restarting the ZPR chain on zpr-core ($ZPR_CORE_IP)..."
ssh_core '
  sudo systemctl stop zpr-egress zpr-vs zpr-vs-adapter zpr-node
  sleep 3
  echo "  node...";        sudo systemctl start zpr-node;       sleep 6
  echo "  vs-adapter...";  sudo systemctl start zpr-vs-adapter; sleep 6
  echo "  visa service..."; sudo systemctl start zpr-vs;        sleep 10
  echo "  egress...";      sudo systemctl start zpr-egress;     sleep 12
'

echo "Verifying the egress adapter was granted a ZPR address..."
if ssh_core "sudo journalctl -u zpr-egress --no-pager --since '30 seconds ago' | grep -q 'granted ZPR addresses'"; then
  echo "OK — chain is healthy. Now rerun:"
  echo "  ./post-init.sh && ./start-device-a.sh && ./start-device-b.sh"
else
  echo "FAILED — egress not granted. Check the auth chain:" >&2
  echo "  ssh -i $KEY opc@$ZPR_CORE_IP 'sudo journalctl -u zpr-vs -u zpr-node -n 40 --no-pager'" >&2
  exit 1
fi
