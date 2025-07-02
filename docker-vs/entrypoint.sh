#!/bin/sh

echo "THIS IS RUNNING"

# Add static IPv4s
ip addr add 129.6.7.1/32 dev eth0

# Ensure socket directory exists
mkdir -p /var/run/zpr

#!/bin/sh

# Wait for the IPv6 address to be assigned
echo "⏳ Waiting for fd5a:5052::2 to appear on eth0..."
while ! ip -6 addr show eth0 | grep -q "fd5a:5052::2"; do
  sleep 0.1
done

echo "✅ IPv6 address assigned, starting service..."
exec /app/bin/vservice -c /authority/vs-config.yaml -p /authority/zpr-full-access.bin -l "[fd5a:5052::2]:5002" &
exec /app/bin/ph-no-uring adapter -c /authority/adapter-vs-conf.toml --debug all
