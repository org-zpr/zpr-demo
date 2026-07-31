#!/bin/sh
# web1: bring up tun9 (matches adapter-web1-conf.toml zpr_addr), then run nginx in
# the foreground (keeps the container alive). The `ph adapter` process is launched
# by deploy-docker.sh via `docker exec`.
set -e

mkdir -p /var/run/zpr   # ph control socket lives here

ip tuntap add name tun9 mode tun multi_queue
ip link set tun9 mtu 1400
ip addr add fd5a:5052:8888::9/32 dev tun9
ip link set tun9 up

exec nginx -g 'daemon off;'
