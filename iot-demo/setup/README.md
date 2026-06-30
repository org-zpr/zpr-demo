# ZPR IoT demo — full-system runbook

Demonstrates ZPR policy enforcement on MQTT traffic, then forwards it to the
Oracle IoT Platform:

```
device_a → ingress adapter (ZPR) → node → egress adapter (ZPR) → mosquitto → [bridge] → OCI IoT
device_b → ingress2 adapter (ZPR) → node → BLOCKED by policy
```

The MQTT broker (mosquitto) runs in the egress container. Devices connect to the egress
adapter's ZPR address — from the device's perspective this is just an IPv6 address.
ZPR routes traffic based on this address: the ingress adapter forwards packets destined
for the egress ZPR address through the ZPR node to the egress adapter, which delivers
them to mosquitto. Devices must also bind to their ingress adapter's ZPR address
(BIND_ADDRESS) so the source IP matches the ZPR actor identity.

The egress mosquitto then bridges device_a's telemetry up to the OCI IoT Platform over
TLS (basic auth). All ZPR addresses are dynamic — discover them from adapter logs after
all adapters connect.

---

## Prerequisites (before each run)

The OCI side is provisioned by Terraform in `../oci-iot` (vault secret, digital twin
model/adapter/instance). Confirm it's applied and refresh the egress bridge credentials:

```bash
# OCI stack applied? (prints the instance OCID)
tofu -chdir=/home/othomas/zpr/demo/iot-demo/oci-iot output device_a_instance_ocid

# Populate setup/egress/.env (gitignored) from tofu outputs — the egress
# container reads it at startup to build the OCI bridge.
cd /home/othomas/zpr/demo/iot-demo/setup/egress && ./gen-env.sh
```

IMPORTANT: start the node (Terminal 1) **before** the egress container (Terminal 6) —
the egress `ph` adapter needs the node up to complete its handshake.

---

## Part A — Bring up the ZPR network

Run each in its own terminal, in order; let each settle before the next.

**Terminal 1 — node:**
```bash
cd /home/othomas/zpr/demo/iot-demo/setup
sudo ./reset-tuns.sh
/home/othomas/zpr/core/target/debug/ph node -c node/node-conf.toml
```

**Terminal 2 — VS adapter:**
```bash
cd /home/othomas/zpr/demo/iot-demo/setup
/home/othomas/zpr/core/target/debug/ph adapter -c vs/adapter-vs-conf.toml
```

**Terminal 3 — Visa service:**
```bash
cd /home/othomas/zpr/demo/iot-demo/setup
valkey-cli flushall
/home/othomas/zpr/visaservice/target/debug/vs -c vs/vs-conf.toml iot-demo.bin2
```

**Terminal 4 — ingress adapter (allowed):**
```bash
cd /home/othomas/zpr/demo/iot-demo/setup
sudo /home/othomas/zpr/core/target/debug/ph adapter -c ingress/ingress-adapter-conf.toml
```

**Terminal 5 — ingress2 adapter (blocked):**
```bash
cd /home/othomas/zpr/demo/iot-demo/setup
sudo /home/othomas/zpr/core/target/debug/ph adapter -c ingress2/ingress2-adapter-conf.toml
```

**Terminal 6 — egress container (mosquitto + egress adapter + OCI bridge):**
```bash
cd /home/othomas/zpr/demo/iot-demo/setup/egress
sudo docker compose up --build
```

✅ **Checkpoint A:** Terminal 6 logs show the egress adapter connect (a
`Link N granted ZPR addresses …` line, *no* `handshake timeout`), then
`Configuring OCI IoT bridge ->` and `Connecting bridge (step 1/2) oci_iot_device_a`.

---

## Part B — Discover addresses & set up routing

```bash
ip link show type tun        # note the ingress / ingress2 TUN names (e.g. tun0, tun1)
```

Grab the three ZPR addresses from the adapter logs (`Link N granted ZPR addresses [IpAddress(V6: <addr>)]`):
- **ingress-addr**  ← Terminal 4
- **ingress2-addr** ← Terminal 5
- **egress-addr**   ← Terminal 6

Set up routing (substitute your discovered values):
```bash
# device_a path: route traffic for the egress address out the ingress TUN
sudo ip -6 route add <egress-addr> dev <ingress-tun>

# device_b path: source-based rule so its traffic uses ingress2 instead
sudo ip -6 rule add from <ingress2-addr> lookup 101
sudo ip -6 route add <egress-addr> dev <ingress2-tun> table 101
```

Note: in production, device_b would be on a separate physical network that naturally
routes through ingress2 — BIND_ADDRESS + the source rule are a single-host demo workaround.

✅ **Checkpoint B:** `ip -6 route get <egress-addr>` shows it routing via the ingress TUN.

---

## Part C — Watch the broker (Terminal 7)

```bash
sudo docker exec -it egress-egress-1 mosquitto_sub -h localhost -p 1883 -t 'devices/#' -v
```
Shows what actually arrives at mosquitto — the midpoint of the chain.

---

## Part D — Run device_a (should flow all the way to OCI) — Terminal 8

```bash
cd /home/othomas/zpr/demo/iot-demo
MQTT_BROKER_HOST=<egress-addr> MQTT_BROKER_PORT=1883 BIND_ADDRESS=<ingress-addr> python3 devices/device_a.py
```

Verify each hop:
- ✅ **device → ZPR → mosquitto:** Terminal 7 prints `devices/device-a/telemetry {...}` every 5s.
- ✅ **mosquitto → OCI:** instance content shows matching temp (20–25) / humidity (40–60):
  ```bash
  oci iot digital-twin-instance get-content \
    --digital-twin-instance-id $(tofu -chdir=/home/othomas/zpr/demo/iot-demo/oci-iot output -raw device_a_instance_ocid)
  ```
  Or watch live in the Console → IoT Platform → ZPR-Demo-Domain → Digital Twin Instances
  → zpr-iot-demo-device-a → content.

---

## Part E — Run device_b (should be blocked) — Terminal 9

```bash
cd /home/othomas/zpr/demo/iot-demo
MQTT_BROKER_HOST=<egress-addr> MQTT_BROKER_PORT=1883 BIND_ADDRESS=<ingress2-addr> python3 devices/device_b.py
```

✅ **Checkpoint E (the policy demo):** device_b should **not** get through — nothing for
`devices/device-b/...` in Terminal 7, and nothing new in OCI. ZPR's policy blocks ingress2.

---

## Reading the result

| Hop | How you know it worked |
|-----|------------------------|
| device_a → ZPR → mosquitto | Terminal 7 shows device-a telemetry |
| mosquitto → OCI | `get-content` / console shows matching temp & humidity |
| device_b blocked | Terminal 7 silent for device-b; OCI unchanged |

**Known gotchas:**
- **Flaky connectivity to OCI** (this host is on WiFi): `get-content` may lag or briefly
  show a stale value. device_a publishes every 5s and the bridge auto-reconnects
  (`restart_timeout 30`, QoS 1), so give it a few cycles. A wired network or the
  OCI-hosted deployment is stable.
- device_a's **timestamp is microsecond-precision + `Z`** (required by the OCI adapter) —
  already handled in `devices/device_a.py`.
- Only **device_a** has an OCI digital twin instance + bridge rule; device_b is both
  blocked by ZPR and has no OCI path.
