#!/usr/bin/env bash
# Start device-a (the ZPR-ALLOWED device). Its telemetry should flow through ZPR to
# mosquitto and on to the OCI IoT Platform.
#
# Prerequisite: run ./post-init.sh once after `tofu apply` (installs the egress
# return-path routing on zpr-core). Rerun this after a stop/start (addresses change).
source "$(dirname "$0")/lib.sh"

start_device ssh_devA zpr-device-a device-a

# echo
# echo "Verify:"
# echo "  broker:  ssh -i $KEY opc@$ZPR_CORE_IP \"mosquitto_sub -h localhost -t 'devices/#' -v\""
# echo "  OCI:     oci iot digital-twin-instance get-content --digital-twin-instance-id \\"
# echo "             \$(tofu -chdir=../oci-iot output -raw device_a_instance_ocid)"
# echo "  stop:    ssh -i $KEY opc@$DEVICE_A_IP 'sudo systemctl stop zpr-device'"
