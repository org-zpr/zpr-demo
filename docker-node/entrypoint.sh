#!/bin/sh

# Add static IPv4s
#ip addr add 129.6.7.2/32 dev eth0
ip addr add 129.6.7.1/32 dev eth0

# Ensure socket directory exists
mkdir -p /var/run/zpr

exec /app/bin/ph-no-uring node -c /authority/node-conf.toml
