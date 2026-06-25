#!/usr/bin/env bash
set -euo pipefail

TUNS=(tun5 tun7 tun8 tun9)

echo "Tearing down TUN interfaces..."
for tun in "${TUNS[@]}"; do
    if ip link show "$tun" &>/dev/null; then
        ip link delete "$tun"
        echo "  deleted $tun"
    else
        echo "  $tun not present, skipping"
    fi
done

echo "Recreating TUN interfaces..."

# tun9 — node (fd5a:5052:90de::1)
ip tuntap add name tun9 mode tun multi_queue
ip link set tun9 mtu 1400
ip addr add fd5a:5052:90de::1/32 dev tun9
ip link set tun9 up
echo "  tun9 up (node: fd5a:5052:90de::1)"

# tun8 — VS adapter (fd5a:5052::1)
ip tuntap add name tun8 mode tun multi_queue
ip link set tun8 mtu 1400
ip addr add fd5a:5052::1/32 dev tun8
ip link set tun8 up
echo "  tun8 up (VS adapter: fd5a:5052::1)"

# tun7 — ingress adapter (fd5a:5052:1::1)
# ip tuntap add name tun7 mode tun multi_queue
# ip link set tun7 mtu 1400
# ip addr add fd5a:5052:1::1/32 dev tun7
# ip link set tun7 up
# echo "  tun7 up (ingress: fd5a:5052:1::1)"

# tun5 — ingress2 adapter (fd5a:5052:1::3)
# ip tuntap add name tun5 mode tun multi_queue
# ip link set tun5 mtu 1400
# ip addr add fd5a:5052:1::3/32 dev tun5
# ip link set tun5 up
# echo "  tun5 up (ingress2: fd5a:5052:1::3)"

echo "Done. Add ingress route manually after adapters connect:"
echo "  sudo ip -6 route add fd5a:5052:1::2 dev <ingress-tun>"
