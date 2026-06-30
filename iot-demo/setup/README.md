The MQTT broker (mosquitto) runs in the egress container. Devices connect to the egress
adapter's ZPR address — from the device's perspective this is just an IPv6 address.
ZPR routes traffic based on this address: the ingress adapter forwards packets destined
for the egress ZPR address through the ZPR node to the egress adapter, which delivers
them to mosquitto. Devices must also bind to their ingress adapter's ZPR address
(BIND_ADDRESS) so the source IP matches the ZPR actor identity.

Both addresses are dynamic — discover them from adapter logs after all adapters connect.

Terminal 1 — Reset TUNs and start the node:

cd /home/othomas/zpr/demo/iot-demo/setup
sudo ./reset-tuns.sh
/home/othomas/zpr/core/target/debug/ph node -c node/node-conf.toml

Terminal 2 — VS adapter:

cd /home/othomas/zpr/demo/iot-demo/setup
/home/othomas/zpr/core/target/debug/ph adapter -c vs/adapter-vs-conf.toml

Terminal 3 — Visa service:

cd /home/othomas/zpr/demo/iot-demo/setup
valkey-cli flushall
/home/othomas/zpr/visaservice/target/debug/vs -c vs/vs-conf.toml iot-demo.bin2

Terminal 4 — Ingress adapter (allowed):

cd /home/othomas/zpr/demo/iot-demo/setup
sudo /home/othomas/zpr/core/target/debug/ph adapter -c ingress/ingress-adapter-conf.toml

Terminal 5 — Ingress2 adapter (blocked):

cd /home/othomas/zpr/demo/iot-demo/setup
sudo /home/othomas/zpr/core/target/debug/ph adapter -c ingress2/ingress2-adapter-conf.toml

Terminal 6 — Egress container:

cd /home/othomas/zpr/demo/iot-demo/setup/egress
sudo docker compose up --build

--- Discover addresses once all adapters are connected ---

Find TUN names: ip link show type tun

From Terminal 4 (ingress) logs:
  "Link N granted ZPR addresses [IpAddress(V6: <ingress-addr>)]"

From Terminal 5 (ingress2) logs:
  "Link N granted ZPR addresses [IpAddress(V6: <ingress2-addr>)]"

From Terminal 6 (egress container) logs:
  "Link N granted ZPR addresses [IpAddress(V6: <egress-addr>)]"

--- Set up routing ---

Route traffic to egress through ingress:

sudo ip -6 route add <egress-addr> dev <ingress-tun>

For device_b — add a higher-priority source-based rule so its traffic goes via ingress2:

sudo ip -6 rule add from <ingress2-addr> lookup 101
sudo ip -6 route add <egress-addr> dev <ingress2-tun> table 101

Note: in production, device_b would be on a separate physical network that
naturally routes through ingress2 — BIND_ADDRESS is a single-host demo workaround.

---

Terminal 7 — Subscribe to see what arrives at the broker:

sudo docker exec -it egress-egress-1 mosquitto_sub -h localhost -p 1883 -t 'devices/#' -v

Terminal 8 — Run device_a (should get through):

cd /home/othomas/zpr/demo/iot-demo
MQTT_BROKER_HOST=<egress-addr> MQTT_BROKER_PORT=1883 BIND_ADDRESS=<ingress-addr> python3 devices/device_a.py

Terminal 9 — Run device_b (should be blocked):

cd /home/othomas/zpr/demo/iot-demo
MQTT_BROKER_HOST=<egress-addr> MQTT_BROKER_PORT=1883 BIND_ADDRESS=<ingress2-addr> python3 devices/device_b.py

DUMMY

sudo ip -6 route add fd5a:5052:adda:1:12b7:78b6:48a0:1983 dev tun0

For device_b — add a higher-priority source-based rule so its traffic goes via ingress2:

sudo ip -6 rule add from fd5a:5052:adda:1:a19f:3fca:839:3e12 lookup 101
sudo ip -6 route add fd5a:5052:adda:1:12b7:78b6:48a0:1983 dev tun1 table 101

Note: in production, device_b would be on a separate physical network that
naturally routes through ingress2 — BIND_ADDRESS is a single-host demo workaround.

---

Terminal 7 — Subscribe to see what arrives at the broker:

sudo docker exec -it egress-egress-1 mosquitto_sub -h localhost -p 1883 -t 'devices/#' -v

Terminal 8 — Run device_a (should get through):

cd /home/othomas/zpr/demo/iot-demo
MQTT_BROKER_HOST=fd5a:5052:adda:1:12b7:78b6:48a0:1983 MQTT_BROKER_PORT=1883 BIND_ADDRESS=fd5a:5052:adda:1:6fea:ae9a:f3c5:4865 python3 devices/device_a.py

Terminal 9 — Run device_b (should be blocked):

cd /home/othomas/zpr/demo/iot-demo
MQTT_BROKER_HOST=fd5a:5052:adda:1:12b7:78b6:48a0:1983 MQTT_BROKER_PORT=1883 BIND_ADDRESS=fd5a:5052:adda:1:a19f:3fca:839:3e12 python3 devices/device_b.py