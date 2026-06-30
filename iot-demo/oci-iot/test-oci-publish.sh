#!/usr/bin/env bash
# Publish one test telemetry message to OCI IoT as device_a, then read the
# digital twin instance content back to confirm the adapter mapped it.
#
# Usage:  ./test-oci-publish.sh [temperature_c] [humidity_pct]
# Example: ./test-oci-publish.sh 31.5 59.9
#
# Requires: ~/bin/oci (OCI CLI), mosquitto_pub, and `tofu apply` already run
# (the connection details come from tofu outputs).
set -uo pipefail
export PATH="$HOME/bin:$PATH"
cd "$(dirname "$0")"

TEMP="${1:-23.5}"
HUM="${2:-50.0}"

# --- connection details, straight from terraform outputs ---
HOST=$(tofu output -raw iot_device_host)
USERNAME=$(tofu output -raw device_a_username)     # "device-a"
PW=$(tofu output -raw device_a_password)           # the vault secret value
INST=$(tofu output -raw device_a_instance_ocid)

# OCI adapter requires microseconds + literal Z
TS=$(python3 -c "from datetime import datetime,timezone;print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ'))")
PAYLOAD="{\"device_id\":\"device-a\",\"sensor_type\":\"temperature_humidity\",\"timestamp\":\"$TS\",\"temperature_c\":$TEMP,\"humidity_pct\":$HUM}"

echo "Broker : $HOST:8883  (topic iot/v1/telemetry)"
echo "Payload: $PAYLOAD"
echo

# Publish, retrying up to 3x to ride out transient keepalive timeouts.
for attempt in 1 2 3; do
  if mosquitto_pub -h "$HOST" -p 8883 \
       --capath /etc/ssl/certs \
       -V mqttv311 -k 30 \
       -i "$USERNAME" -u "$USERNAME" -P "$PW" \
       -t iot/v1/telemetry -m "$PAYLOAD" -q 1; then
    echo "published (attempt $attempt)"
    break
  fi
  echo "attempt $attempt failed (transient), retrying..."
  sleep 2
done

echo
echo "Reading instance content (latest state — ephemeral, read promptly):"
sleep 3
oci iot digital-twin-instance get-content --digital-twin-instance-id "$INST"
