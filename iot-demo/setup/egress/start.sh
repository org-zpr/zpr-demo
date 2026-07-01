#!/usr/bin/env bash
set -e

mkdir -p /var/run/zpr

# Resolve host gateway IP and write a runtime config with the literal IP
HOST_IP=$(getent hosts host.docker.internal | awk '{ print $1 }')
sed "s/host.docker.internal/$HOST_IP/" /app/adapter-conf.toml > /tmp/adapter-conf.toml

# Start egress adapter in background
/app/ph adapter -c /tmp/adapter-conf.toml &

# Give the adapter a moment to connect before Mosquitto starts
sleep 2

# Build the runtime Mosquitto config: base listener + (optional) OCI IoT bridge.
# The bridge stanza mirrors the cloudlabs iot_edge mosquitto.conf.j2, with basic
# (username/password) auth instead of mTLS. Credentials come from env vars
# (set via setup/egress/.env, populated from `tofu output`).
cp /etc/mosquitto/conf.d/zpr.conf /tmp/zpr.conf
# All-or-nothing: if ANY OCI var is set, require ALL three, so partial creds fail
# loudly here instead of producing a broken bridge stanza that dies at connect time.
if [ -n "${OCI_DEVICE_HOST:-}" ] || [ -n "${OCI_DEVICE_USERNAME:-}" ] || [ -n "${OCI_DEVICE_PASSWORD:-}" ]; then
  : "${OCI_DEVICE_HOST:?missing OCI_DEVICE_HOST}"
  : "${OCI_DEVICE_USERNAME:?missing OCI_DEVICE_USERNAME}"
  : "${OCI_DEVICE_PASSWORD:?missing OCI_DEVICE_PASSWORD}"
  echo "Configuring OCI IoT bridge -> ${OCI_DEVICE_HOST}"
  cat >> /tmp/zpr.conf <<EOF

# --- OCI IoT Platform bridge (device_a, basic auth over TLS) ---
connection oci_iot_device_a
address ${OCI_DEVICE_HOST}:8883
bridge_capath /etc/ssl/certs
bridge_protocol_version mqttv311
remote_clientid ${OCI_DEVICE_USERNAME}
remote_username ${OCI_DEVICE_USERNAME}
remote_password ${OCI_DEVICE_PASSWORD}
try_private false
cleansession true
keepalive_interval 60
restart_timeout 30
start_type automatic
notifications false
topic "" out 1 devices/device-a/telemetry iot/v1/telemetry
EOF
else
  echo "OCI bridge credentials not set — starting Mosquitto without the OCI bridge."
fi

# Start Mosquitto in foreground
mosquitto -c /tmp/zpr.conf
