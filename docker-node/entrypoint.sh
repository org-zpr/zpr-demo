#!/bin/sh

ip addr add 129.6.7.1/32 dev eth0

mkdir -p /var/run/zpr

exec /app/bin/ph-no-uring node -c /authority/node-conf.toml
