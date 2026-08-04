#!/usr/bin/env bash
# Publish one telemetry message to OCI IoT as device_a — PUBLISH ONLY.
# Then verify it in the OCI Console (digital twin instance content view).
#
# Usage:
#   ./publish-oci.sh             # random values (20-25C / 40-60%)
#   ./publish-oci.sh 27.8 44.1   # specific temp / humidity
set -uo pipefail
export PATH="$HOME/bin:$PATH"
cd "$(dirname "$0")"

HOST=$(tofu output -raw iot_device_host)
USERNAME=$(tofu output -raw device_a_username)
PW=$(tofu output -raw device_a_password)

rand() { python3 -c "import random;print(round(random.uniform($1,$2),2))"; }
TEMP="${1:-$(rand 20 25)}"
HUM="${2:-$(rand 40 60)}"
TS=$(python3 -c "from datetime import datetime,timezone;print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ'))")
PAYLOAD="{\"device_id\":\"device-a\",\"sensor_type\":\"temperature_humidity\",\"timestamp\":\"$TS\",\"temperature_c\":$TEMP,\"humidity_pct\":$HUM}"

echo "Publishing to $HOST  (topic iot/v1/telemetry)"
echo "  temp=$TEMP  humidity=$HUM"
mosquitto_pub -h "$HOST" -p 8883 --capath /etc/ssl/certs -V mqttv311 -k 30 \
  -i "$USERNAME" -u "$USERNAME" -P "$PW" -t iot/v1/telemetry -m "$PAYLOAD" -q 1 \
  && echo "sent — check the instance content in the Console."
