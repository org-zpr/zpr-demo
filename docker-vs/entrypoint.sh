#!/bin/sh


mkdir -p /var/run/zpr

ip tuntap add name tun9 mode tun multi_queue
ip link set tun9 mtu 1400
ip addr add fd5a:5052::1/32 dev tun9
ip link set tun9 up

# Docker should have started node before this.
# Give node a few secs to startup.
sleep 7

exec /app/bin/vservice -c /authority/vs-config.yaml -p /authority/zpr-full-access.bin &

# Let visa service intialize...
# TODO: it does not need 20secs, but this is helpful for debugging the output
sleep 20

# Start adapter which will immeidately try to connect to the node.
exec /app/bin/ph adapter -c /authority/adapter-vs-conf.toml --debug all
