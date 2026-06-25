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

# Start Mosquitto in foreground
mosquitto -c /etc/mosquitto/conf.d/zpr.conf
