# ZPR IoT demo on OCI — topology

Moves the whole demo (currently run across 9 terminals on one laptop) onto three
OCI compute instances. ZPR still does the policy enforcement; OCI just provides
the hosts and the network they sit on.

## The picture

Everything on zpr-core runs as **native processes — no Docker** (see "Native, no
Docker" below).

```
                          ┌───────────────────────────────────────────────┐
   ┌──────────────┐       │  Instance 3: zpr-core (all native)             │
   │ Instance 1:  │       │                                                │
   │ device-a     │       │  valkey ── visa service (vs) ──┐               │
   │              │  UDP  │       (TCP+valkey, localhost)   │               │
   │ device_a.py  │ 5000  │  node (ph) ─── VS adapter (ph) ─┘  tun8/tun9    │
   │ device-a(ph) ├──────►│    ▲  self_addr 0.0.0.0:5000                    │
   │  tunX        │       │    │                                            │
   └──────────────┘       │    └── egress adapter (ph, dials 127.0.0.1:5000)│
                          │        mosquitto (1883, localhost)             │
   ┌──────────────┐       │        + OCI bridge ──────────────┐            │
   │ Instance 2:  │  UDP  │                                    │            │
   │ device-b     │ 5000  │                                    │            │
   │ device_b.py  ├──────►│                                    │            │
   │ device-b(ph) │       └────────────────────────────────────┼───────────┘
   │  tunY        │  (BLOCKED by ZPR policy at the node)        │ TLS 8883
   └──────────────┘                                             ▼
                                                     OCI IoT Platform
                                                    (public endpoint)
```

## Instances (all VM.Standard.E5.Flex, 1 OCPU / ~4 GB, Oracle Linux 9)

| Instance | Runs | Privileges | Talks to |
|----------|------|-----------|----------|
| **device-a** | `device_a.py`, device-a adapter (`ph`) | needs TUN (NET_ADMIN / sudo) | zpr-core:5000/udp |
| **device-b** | `device_b.py`, device-b adapter (`ph`) | needs TUN | zpr-core:5000/udp (dropped by policy) |
| **zpr-core** | valkey, node (`ph`), VS adapter (`ph`), visa service (`vs`), egress adapter (`ph`), mosquitto + OCI bridge — all native | needs TUN | OCI IoT :8883 outbound |

Everything in **one public subnet** (e.g. `10.0.0.0/24`). ZPR is the access-control
layer; the OCI network just needs to not silently block the substrate.

## Ports / traffic matrix

| From | To | Port | Proto | Why |
|------|----|----|-------|-----|
| device-a, device-b | zpr-core | 5000 | **UDP** | ZPR substrate (adapter → node). Confirmed UDP (`socket2::Type::DGRAM`). |
| operator laptop | all three | 22 | TCP | SSH for provisioning + post-init hand-off |
| zpr-core | OCI IoT public endpoint | 8883 | TCP | mosquitto → OCI bridge (TLS) |
| *(within zpr-core, localhost only — no subnet rule needed)* | | | | VS↔vs is TCP; valkey 6379; mosquitto 1883 |

## Two firewall layers — both default-deny, both fail silently (per ats)

1. **OCI security list / NSG on the subnet.** Default drops inter-instance UDP even
   within the same subnet. Terraform must add an ingress rule allowing **5000/udp**
   from the subnet CIDR (simplest: allow-all from `10.0.0.0/24`), plus 22/tcp from
   the operator. Egress to `0.0.0.0/0` (for the 8883 bridge + package installs).
2. **Host `firewalld` on Oracle Linux 9** (ships enabled). Even with the security
   list open, firewalld drops the substrate. cloud-init must open **5000/udp** on
   zpr-core (or stop firewalld for the demo).

If ZPR handshakes hang with no error, it's almost always one of these two.

## Native, no Docker (decision)

The single-host demo containerized mosquitto **solely** for network isolation — to
stop a device from bypassing ZPR and hitting `localhost:1883` directly. With devices
on separate instances that shortcut no longer exists: the only path to mosquitto's
1883 is across the network through the ZPR substrate. The instance boundary now
provides the isolation the container used to.

So zpr-core runs **everything natively, no Docker**:

- Drops Docker as a dependency (no image build/pull, no `--cap-add NET_ADMIN` /
  `/dev/net/tun` juggling for the egress adapter's TUN).
- cloud-init just `dnf install`s mosquitto + valkey and drops the `ph`/`vs` binaries.
- The container's `start.sh` logic (build mosquitto config, append the OCI bridge
  stanza from `.env`) becomes a plain boot script / systemd `ExecStartPre`. The
  `bridge_capath /etc/ssl/certs` works as-is — OL9 ships the CA bundle there.

## Artifact & config distribution — the split

`ph` / `vs` are not public packages, and each role needs certs + config. Two
delivery channels, chosen by what each file is:

- **big / static / same-everywhere → Object Storage** (pull at boot): the `ph`/`vs`
  binaries, `iot-demo.bin2`, and cert/key files. Uploaded as `oci_objectstorage_object`
  resources (auto re-upload on rebuild; only a hash in state). One `AnyObjectRead`
  **PAR** gives cloud-init a credential-free URL to curl from — instance principals
  aren't usable (need a tenancy dynamic group + policy this account lacks). Bucket
  layout: `bin/ shared/ core/ device-a/ device-b/`.
- **small / needs-a-computed-value → cloud-init user_data** (baked at launch): the
  `.toml` configs. Their `node_addr` differs per role (zpr-core private IP for the
  device adapters, `127.0.0.1` for the co-located egress/VS adapters) and Terraform
  only knows the private IP after create — so they're rendered with `templatefile()`
  into each instance's cloud-init, not staged in the bucket.

cloud-init on each instance then installs deps (valkey + mosquitto on zpr-core;
python3 on the device hosts), opens firewalld (layer 2), curls its artifacts from
the PAR, drops the rendered configs, installs systemd units, and starts its processes.

The CA **private** key (`authority/auth-ca.key`) is never uploaded — only `auth-ca.crt`
ships. Binaries are debug builds for now (paths are variables; switch to `target/release`
for smaller uploads once built).

## Address discovery — the hand-off (option 1: post-init script)

ZPR grants **dynamic** ZPR addresses to the device-a, device-b, and egress adapters at
runtime (`Link N granted ZPR addresses [IpAddress(V6: …)]`). The node and VS addresses
are static in config; these three are not knowable until the adapters connect.

After `tofu apply` brings all three instances up and running, run `post-init.sh`:

1. SSH to **zpr-core**, read `journalctl -u zpr-egress` → **egress-addr** (the
   destination devices publish to).
1b. On **zpr-core**, install source-based policy routing so egress replies exit the
   egress tun (see "Deployment gotchas" — the overlapping-route fix).
2. `start-device-a.sh`: SSH to **device-a**, read `journalctl -u zpr-device-a` →
   **device-a-addr**. Add the route (`ip -6 route replace <egress-addr> dev <tun>`),
   write `device.env`, and start the `zpr-device` publisher unit
   (`MQTT_BROKER_HOST=<egress-addr>`, `BIND_ADDRESS=<device-a-addr>`).
3. `start-device-b.sh`: same via `zpr-device-b` (it is blocked at the node — that's
   the demo).

Rerun after any stop/start — restarted adapters get NEW dynamic addresses.

## Deployment gotchas (learned on first real deploy — all fixed in the templates)

1. **glibc** — laptop-built `ph`/`vs` need glibc 2.38/2.39; OL9 has 2.34. Build in an
   OL9 container (`build-in-ol9.sh` → `$ZPR_BUILD_DIR/target/release/`, default
   `~/.cache/zpr-oci-build/target/release/`). musl ruled out (openssl-sys
   + aws-lc-sys/cmake). Build deps need EPEL + CodeReady Builder repos.
2. **EPEL** — valkey + mosquitto live in EPEL, disabled by default; enable it first.
   No separate `mosquitto-clients` pkg (tools ship in `mosquitto`).
3. **AA-registration startup race** — the node registers its auth authority once, early;
   parallel systemd start races it and fails permanently. Fixed with `ExecStartPre`
   readiness gates: VS adapter waits for the node's port; visa service waits for the VS
   adapter to go ACTIVE.
4. **`/var/run/zpr`** — the adapter's control-socket dir; add `RuntimeDirectory=zpr`
   (+ `RuntimeDirectoryPreserve=yes`, since 3 units share it on zpr-core).
5. **mosquitto config** — OL9's `mosquitto.conf` doesn't `include_dir conf.d` (Debian's
   does); append it or mosquitto runs localhost-only with no bridge.
6. **firewalld** — open `1883/tcp` (MQTT on the egress tun) alongside `5000/udp`.
7. **Overlapping `/32` routes (the big one)** — node/vs/egress all carry `fd5a:5052::/32`
   in one namespace, so egress's TCP replies route out the node's tun and device
   handshakes never complete. `post-init.sh` installs source-based policy routing
   (`ip -6 rule from <egress-addr> lookup 100` → route via the egress tun). This is the
   consequence of native co-location that the laptop dodged via container namespaces —
   the one place the "native, no Docker" decision cost us.

## Decisions made

- **Native, no Docker on zpr-core** (see above). Isolation now comes from the
  instance boundary, not a container namespace.
- **systemd units** supervise the ZPR processes (one unit each: valkey, node,
  VS adapter, visa service, egress adapter, mosquitto). Ordering via
  `After=`/`Requires=` (node before adapters, valkey before vs); `Restart=on-failure`
  (useful given the known chrono panic); `Environment=TZ=UTC`. Gives post-init.sh a
  deterministic log source (`journalctl -u <unit>`) to scrape the granted address from.
- **SSH key**: dedicated `~/.ssh/zpr-demo` pair (ed25519). The public half is
  injected into all three instances at launch; the private half stays on the
  operator laptop for SSH + the `post-init.sh` hand-off. Isolated from personal
  keys — delete with the demo.
- **Cost hygiene**: x86 compute is billed only while instances are *running*.
  Two ways to pause between demos:
  - **Stop** (OCI "pause") — halts compute billing, keeps boot volumes (a few
    $/month total), reboots in ~1 min. Use for short gaps / same-day resumes.
    Note: ZPR re-grants dynamic addresses on restart, so rerun `post-init.sh`.
  - **`tofu destroy`** — $0, but a full re-apply + cloud-init + post-init to
    rebuild (minutes). Use when away for a while, to keep the tenancy clean.
