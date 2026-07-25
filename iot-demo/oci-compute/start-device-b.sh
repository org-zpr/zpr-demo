#!/usr/bin/env bash
# Start device-b (the ZPR-BLOCKED device). It connects through the device-b adapter
# (cert CN device-b.zpr.org), which the policy does not allow, so the visa service
# denies its flow and its publisher just times out. This is the policy demo.
#
# Prerequisite: run ./post-init.sh once after `tofu apply`. Rerun after a stop/start.
source "$(dirname "$0")/lib.sh"

start_device ssh_devB zpr-device-b device-b

# echo
# echo "Verify it is blocked BY THE VISA SERVICE (not just silent):"
# echo "  watch denials:  ssh -i $KEY opc@$ZPR_CORE_IP 'sudo journalctl -u zpr-vs -f'"
# echo "    -> 'visa request from ... denied (no match): no matching policy'"
# echo "  device view:    ssh -i $KEY opc@$DEVICE_B_IP 'sudo journalctl -u zpr-device -n 20'"
# echo "    -> socket.timeout: timed out"
# echo "  stop:           ssh -i $KEY opc@$DEVICE_B_IP 'sudo systemctl stop zpr-device'"
