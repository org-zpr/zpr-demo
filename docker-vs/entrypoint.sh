#!/bin/sh

# Docker compose will not start visa service until
# it has "started" the node. However, just starting
# the node does not mean it is up and ready for 
# interactions.  So we have some sleeps in here.

mkdir -p /var/run/zpr

ip tuntap add name tun9 mode tun multi_queue
ip link set tun9 mtu 1400
ip addr add fd5a:5052::1/32 dev tun9
ip link set tun9 up

# XXX wait on node
sleep 7

exec /app/bin/vservice -c /authority/vs-config.yaml -p /authority/m4-demo-0818.bin &

# XXX Let visa service intialize...
sleep 7

# Start adapter which will immeidately try to connect to the node.
exec /app/bin/ph adapter -c /authority/adapter-vs-conf.toml --debug all
