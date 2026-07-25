# oci-compute — run the ZPR IoT demo on OCI compute

Provisions the three-instance OCI topology that runs the whole ZPR demo (node,
visa service, adapters, mosquitto + OCI bridge, and both devices) instead of the
9-terminal single-laptop setup. See [TOPOLOGY.md](TOPOLOGY.md) for the diagram,
port matrix, and the decisions behind this layout.

> **Status: working end-to-end on OCI.** Verified 2026-07-06 — clean `tofu apply` →
> all services up on first boot → `post-init.sh` → device_a telemetry reaches the OCI
> digital twin; device_b blocked by ZPR policy. See TOPOLOGY.md "Deployment gotchas"
> for the issues found and fixed along the way.

## Layout

| File | Purpose |
|------|---------|
| `provider.tf` | OCI provider (profile DEFAULT) |
| `variables.tf` / `terraform.tfvars` | inputs; real compartment/region in tfvars |
| `network.tf` | VCN, subnet, IGW, route table, **security list (layer-1 firewall)** |
| `compute.tf` | the three instances (device-a, device-b, zpr-core) |
| `objectstorage.tf` | bucket for staging `ph`/`vs`/policy/cert bundles |
| `cloud-init/*.tftpl` | per-role first-boot config (**layer-2 firewall**, deps, start) |
| `outputs.tf` | public/private IPs + ready-to-paste SSH commands |
| `lib.sh` | shared helpers (SSH, address discovery, `start_device`) — sourced, not run |
| `post-init.sh` | one-time zpr-core setup after `tofu apply` (egress addr + return-path routing) |
| `restart-core.sh` | sequentially restart the zpr-core ZPR chain (after a binary swap / clean bounce) |
| `vs-admin.sh` | run `vs-admin` locally against the visa service admin API over an SSH tunnel |
| `start-device-a.sh` | start the ZPR-allowed device (telemetry → OCI) |
| `start-device-b.sh` | start the ZPR-blocked device (denied by the visa service) |

## Apply

Prerequisite: the `../oci-iot` stack must be applied (this root reads its outputs
for the mosquitto→OCI bridge credentials via `terraform_remote_state`).

```bash
tofu init
tofu plan
tofu apply
./post-init.sh          # one-time zpr-core setup (egress addr + return-path routing)
./start-device-a.sh     # start the allowed device
./start-device-b.sh     # start the blocked device
```

## Run it yourself — step by step

### 0. Prerequisites

- **OpenTofu/Terraform** and the **OCI CLI** (`oci`) on `$PATH`, with `~/.oci/config`
  profile `DEFAULT` pointing at the ZPR-IoT-Demo tenancy.
- **The `../oci-iot` stack applied** (`tofu -chdir=../oci-iot apply`) — this root reads
  its outputs for the OCI bridge credentials.
- **SSH keypair** at `~/.ssh/zpr-demo` (public half is injected into the instances).
  Generate once if missing: `ssh-keygen -t ed25519 -f ~/.ssh/zpr-demo -N ""`.
- **OL9-compatible binaries**: `ph`/`vs` must be built against Oracle Linux 9's glibc,
  not your laptop's. Run `./build-in-ol9.sh` (needs Docker); it writes the binaries to
  `zpr/oci-build/release/`, which is where `variables.tf` (`ph_binary_path` /
  `vs_binary_path`) already points.

### 1. Deploy

```bash
tofu init
tofu apply                    # ~2 min: network, bucket+artifacts, 3 instances
```

Wait for zpr-core's cloud-init to finish (installs packages, pulls artifacts, starts
the ZPR stack — ~2-3 min after the instance appears):

```bash
CORE=$(tofu output -raw zpr_core_public_ip)
ssh -i ~/.ssh/zpr-demo opc@$CORE 'sudo cloud-init status --wait'
```

`cloud-init status` reports one of: `not run`, `running`, `done`, `error`, or the edge
cases `disabled` / `degraded done` (degraded = finished with recoverable errors). Use
**`--wait`**, not a `grep -q done` polling loop: `--wait` blocks until cloud-init reaches
a terminal state (done *or* error), prints dots while it works, then exits `0` on success
and non-zero on error/degraded. A `grep done` loop, by contrast, spins **forever** if
cloud-init errors (e.g. a failed package install) — you'd think it's still booting when
it has actually failed. `--wait` can't hang on failure and gives a clear signal either way.

Then set up zpr-core (discovers the dynamic egress address, installs the egress
return-path routing) and start each device:

```bash
CORE=$(tofu output -raw zpr_core_public_ip)
./post-init.sh          # one-time zpr-core setup — run before the device scripts
```

The two device scripts are independent — you can start/stop either on its own (e.g.
start device-a, confirm OCI is receiving, then start device-b and watch it get denied).
Rerun `post-init.sh` first after any stop/start of zpr-core (the egress address changes).

Handy: `tofu output ssh_commands` prints ready-to-paste SSH commands for all three hosts.

### 2. Verify the ZPR stack on zpr-core is healthy

```bash
CORE=$(tofu output -raw zpr_core_public_ip)
ssh -i ~/.ssh/zpr-demo opc@$CORE \
  'for u in valkey zpr-tuns zpr-node zpr-vs-adapter zpr-vs zpr-egress mosquitto; do
     printf "%-16s %s\n" $u $(systemctl is-active $u.service); done'
```

All seven should read `active`. (If `zpr-vs`/adapters are `activating`, the auth
authority didn't register — see TOPOLOGY.md gotcha #3.)

### 3. Verify device_a telemetry reaches the broker (the ZPR-allowed path)

This proves device_a → device-a adapter → node → egress → mosquitto works:

```bash
CORE=$(tofu output -raw zpr_core_public_ip)
ssh -i ~/.ssh/zpr-demo opc@$CORE \
  "mosquitto_sub -h localhost -p 1883 -t 'devices/#' -v"
```

Expect a `devices/device-a/telemetry {…}` line every ~5s. **Only device-a** should
appear here — device-b never reaches the broker.

### 4. Verify the data reaches the OCI IoT Platform

This proves the mosquitto→OCI bridge works (the final hop):

```bash
INST=$(tofu -chdir=../oci-iot output -raw device_a_instance_ocid)
watch -n 1 "oci iot digital-twin-instance get-content --digital-twin-instance-id $INST --query data"
```

```bash
CORE=$(tofu output -raw zpr_core_public_ip)
./start-device-a.sh     # allowed device — telemetry should flow to OCI
```

```bash
./start-device-b.sh     # blocked device — denied by the visa service
```

The returned `content` shows `temperature_c` / `humidity_pct` matching what device_a
is publishing (20-25 °C / 40-60 %). Re-run it and the values track the live stream.
Or watch it in the Console: **IoT → ZPR-Demo-Domain → Digital Twin Instances →
zpr-iot-demo-device-a → Content**.

### 5. Verify device_a is granted a visa *by the visa service*

Symmetric to the block below: device_a's flow is authorized by the visa service, which
logs the grant as a `created visa` line. A grant is **cached** (long-lived), so it's
logged once and device_a then runs quietly — unlike device_b's denials, which repeat
every second because a denied flow is never cached. So to *watch* a grant happen you
force a fresh device_a flow (restarting its adapter gives it a new ZPR address,
which triggers a new visa request):

```bash
CORE=$(tofu output -raw zpr_core_public_ip)
DA=$(tofu output -raw device_a_public_ip)

# terminal 1 — follow the visa service on zpr-core:
ssh -i ~/.ssh/zpr-demo opc@$CORE 'sudo journalctl -u zpr-vs -f'

# terminal 2 — force a fresh device_a flow:
ssh -i ~/.ssh/zpr-demo opc@$DA 'sudo systemctl restart zpr-device-a'   # new address
./start-device-a.sh                                                    # re-wire + publish
```

In terminal 1 you'll see the grant appear:

```
vs::visa_mgr: created visa 1004
```

That is the visa service authorizing device_a's `device-a.zpr.org → egress.zpr.org` flow
(the policy's single `allow` rule). Contrast with device_b, which never gets one.

### 6. Verify device_b is genuinely blocked *by the visa service*

Getting no device-b data isn't enough — we want to *see* the visa service deny it.
On zpr-core, follow the visa service log while device_b keeps trying:

```bash
ssh -i ~/.ssh/zpr-demo opc@$CORE 'sudo journalctl -u zpr-vs -f'
```

You'll see a denial roughly every second:

```
vreq: visa request from fd5a:5052:90de::1 denied (no match): no matching policy
```

Those come from the node (`fd5a:5052:90de::1`) on device_b's behalf: device_b connects
through the **device-b** adapter (cert CN `device-b.zpr.org`), and the policy
(`iot-demo.zpl`) only allows `device-a.zpr.org → egress.zpr.org`, so device-b matches no
rule and is denied — where device_a got a `created visa` (step 5), device_b gets
`denied (no match)`.

**Prove the denials are device_b, not noise** — stop device_b's publisher and watch the
denials stop, then start it and watch them resume:

```bash
DB=$(tofu output -raw device_b_public_ip)
ssh -i ~/.ssh/zpr-demo opc@$DB 'sudo systemctl stop zpr-device'   # denials stop
ssh -i ~/.ssh/zpr-demo opc@$DB 'sudo systemctl start zpr-device'  # denials resume
```

For the device's own view of being blocked, its publisher times out on connect:

```bash
ssh -i ~/.ssh/zpr-demo opc@$DB 'sudo journalctl -u zpr-device -n 20'
# -> socket.timeout: timed out  (the SYN is dropped at the node; no visa)
```

## Visa service admin (vs-admin)

The visa service exposes an admin HTTPS API on `https://[fd5a:5052::1]:8182` (bound on
tun8). It needs an API key, and the endpoint is only reachable on zpr-core itself.

**One-time: create an API key on zpr-core** (writes `/vs_keys.toml`, which the vs reads;
prints the key). `vsapikey` is in the OL9 build — copy it over if not already there:

```bash
CORE=$(tofu output -raw zpr_core_public_ip)
scp -i ~/.ssh/zpr-demo ~/zpr/oci-build/release/vsapikey opc@$CORE:/tmp/
ssh -i ~/.ssh/zpr-demo opc@$CORE 'sudo install -m0755 /tmp/vsapikey /usr/local/bin/
  KEY=$(sudo /usr/local/bin/vsapikey create readwrite admin /vs_keys.toml --init --desc admin)
  sudo systemctl kill -s SIGUSR2 zpr-vs   # reload keys, no restart
  echo "$KEY"'
# paste the printed key into oci-compute/.vs-admin.key (gitignored)
```

`vsapikey create <read|readwrite> <owner> [keyfile] [--init]`; the vs reloads its key
file on **SIGUSR2** (no restart, so no AA-race risk).

**Then use `vs-admin` locally over an SSH tunnel** — `./vs-admin.sh <args>` opens a
forward to the admin endpoint, runs your laptop's `vs-admin`, and closes the tunnel.
Because the forwarded connection originates on zpr-core it counts as same-host (no extra
ZPR policy needed):

```bash
./vs-admin.sh actors        # list actors (node, egress, vs, devices)
./vs-admin.sh services      # list services (incl. OracleIoT)
./vs-admin.sh policies --curr
./vs-admin.sh stats
```

Build a current `vs-admin` on your laptop first (`cd ~/zpr/visaservice && cargo build
--release -p vs-admin`) so its subcommands match the running vs. Paths are overridable
via `VSADMIN` / `VS_CA` / `VS_KEYFILE` env vars.

## Unverified assumptions (check on first apply / boot)

- EPEL package + service names on Oracle Linux 9: `oracle-epel-release-el9`,
  `valkey`/`valkey.service`, `mosquitto`/`mosquitto.service`. Adjust if they don't start.
- `instance_image_id` (variables.tf) is a pinned OL9 image OCID — confirm it's current.
- Substrate is **UDP 5000**: zpr-core opens it in firewalld (it listens); device
  instances are outbound-only so need no inbound rule.
- The device password is baked into zpr-core's `user_data` (base64, not encrypted) —
  visible in instance metadata. Acceptable for a demo; note it for a shared deployment.

## Cost hygiene

x86 compute bills only while running. Between demos:
- **Stop** the instances (OCI pause) for short gaps — compute billing halts, boot
  volumes persist (~$few/month), ~1 min reboot. Rerun `post-init.sh` after (ZPR
  re-grants dynamic addresses on restart).
- **`tofu destroy`** when away longer — $0, but a full re-apply to rebuild.
