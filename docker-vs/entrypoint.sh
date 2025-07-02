#!/bin/sh

ip addr add 129.6.7.1/32 dev eth0

mkdir -p /var/run/zpr

exec /app/bin/vservice -c /authority/vs-config.yaml -p /authority/zpr-full-access.bin -l "[fd5a:5052::2]:5002" &
exec /app/bin/ph-no-uring adapter -c /authority/adapter-vs-conf.toml --debug all
