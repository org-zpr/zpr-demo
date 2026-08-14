# Multinode Demo

## Contents

- `bin` - Binaries to run for the demo
- `commands` - Operator commands for driving a running demo (see below).
- `local-compute` - Setup code for the local ("on prem") containers.
- `oci-compute` - OpenTofu setup for the remote (OCI cloud) instances.
- `zpr-conf` - All the ZPR config files, certificates, policy, etc.

## Handy commands (`commands/`)

Once both environments are deployed, `commands/` wraps the long-form incantations
documented further down — one name per ZPR process, one way to reach each. The long
forms are kept below on purpose: they're the reference when a command misbehaves.

| command | what it does |
|---|---|
| `demo-status` | is every `ph` up? last 10 log lines each. Exit 1 if any is down |
| `demo-check-ph <NAME>` | the same, for one process. Exit 1 when down |
| `demo-watch-ph <NAME>` | `tail -f` its log. `-a` attaches to the tmux session instead |
| `demo-restart-ph <NAME>` | relaunch it, using the config the deploy already placed |
| `demo-stop-ph <NAME>…` | stop one or more, host/container left up. Restart with the above |
| `demo-shell <NAME>` | interactive shell there, in its ZPR working dir |
| `demo-watch-vs` | `tail -f` the **visa service** log (not its adapter) |
| `demo-vs-admin <CMD…>` | `vs-admin` with `--svc-url`, `--ca-cert` and the API key filled in |
| `demo-vs-admin-gui` | alias for `demo-vs-admin gui` |
| `demo-zpr-dashboard` | the `zpr-dashboard` TUI — richer than `demo-vs-admin gui` |
| `demo-attr <set\|add\|rm\|del\|show\|push\|save\|selftest>` | edit the attribute file + flush the vs cache |

`<NAME>` is one of:

| NAME | what | where |
|---|---|---|
| `node0` | substrate node | OCI `node` |
| `ociweb` | web adapter | OCI `webserver` |
| `admin` | admin user's adapter (runs as root) | OCI `admin` |
| `node1` | substrate node | docker `node1` |
| `vs` | the visa service's **adapter** | docker `vs` |
| `premweb` | web adapter | docker `web1` |

OCI addresses come from `tofu output` at call time — nothing to regenerate after a
`tofu apply`. Override the SSH key with `SSH_KEY=/path`.

`demo-attr` is the one with a self-check: `commands/demo-attr selftest` exercises its
jq transforms offline, no infra needed.

**Attributes are tags, not values.** The `.zplc` maps each attribute to a tag
(`prem_user -> #user.prem_user`), so the mere *presence* of the key sets it —
`demo-attr set admin.demo prem_user no` **grants** `prem_user`. `demo-attr del` is the
only way to revoke.

## How to install (OCI hosts)

Brings up three Ubuntu 24.04 instances in OCI — SSH-reachable and able to reach
each other by private IP:

| host        | role                                        | `tun9`                  |
|-------------|---------------------------------------------|-------------------------|
| `node`      | ZPR substrate node (node0), 5000 tcp+udp    | `fd5a:5052:90de::10`    |
| `webserver` | nginx + landing page (`oci-compute/web/`)   | `fd5a:5052:8888::8`     |
| `admin`     | "admin user" workstation, runs an adapter   | none — dynamic ZPR addr |

No ZPR components yet at this stage.

**Prerequisites:** `tofu` + `oci` CLIs installed, `~/.oci/config` set up (profile
`DEFAULT`), and the demo SSH key present at `~/.ssh/zpr-demo(.pub)`.

**Apply:**

```bash
cd oci-compute
tofu init
tofu plan
tofu apply
```

**Get IPs and SSH in:**

```bash
tofu output              # public_ips, private_ips, ssh_commands
ssh -i ~/.ssh/zpr-demo ubuntu@<public_ip>
```

**Verify (per host):**

```bash
ip addr show tun9                       # role's fd5a:... address, state UP (not on admin)
ping <other-host-private-ip>            # inter-host IP works
curl http://<webserver_public_ip>/      # "hello from OCI"
```

**Re-push the webserver index:** cloud-init only runs at first boot, so editing
`oci-compute/web/index.html` and re-applying does NOT repaint a live host. Either:

```bash
scp oci-compute/web/index.html ubuntu@<web_ip>:/tmp/ && \
  ssh ubuntu@<web_ip> 'sudo mv /tmp/index.html /var/www/html/'
# or rebuild just that host:
tofu apply -replace='oci_core_instance.host["webserver"]'
```

**Tear down:** `tofu destroy`.

## How to deploy & run ZPR (OCI hosts)

Once the infra is up, `oci-compute/deploy-zpr.sh` puts the `ph` binary + configs
on all three hosts, injects the node's private IP into the adapter configs, and
starts each `ph` in a detached `tmux` session in the right order. See
[`tf-configure-run-zpr.md`](work/tf-configure-run-zpr.md) for the design.

**Deploy:**

```bash
cd oci-compute
./deploy-zpr.sh              # reads addresses from `tofu output`
```

It's re-runnable: the ~200 MB `ph` upload is skipped when the host already has a
same-size copy, and each `ph` is restarted cleanly (old tmux session killed
first). Re-run after any `tofu apply` that recreated the `node` (its private IP
is what gets injected). Override the SSH key with `SSH_KEY=/path ./deploy-zpr.sh`.

It also writes `premweb.demo` (`fd5a:5052:8888::9`) and `ociweb.demo`
(`fd5a:5052:8888::8`) into the **admin** host's `/etc/hosts`, so
`curl http://ociweb.demo/` works from there once the demo is up.

**Watch a `ph` process** (session name = mode: `node` or `adapter`; Ctrl-b d to
detach):

```bash
ssh -i ~/.ssh/zpr-demo -t ubuntu@<node_public_ip>  tmux attach -t node
ssh -i ~/.ssh/zpr-demo -t ubuntu@<web_public_ip>   tmux attach -t adapter
ssh -i ~/.ssh/zpr-demo -t ubuntu@<admin_public_ip> tmux attach -t adapter
```

**Check state without attaching:**

```bash
ssh -i ~/.ssh/zpr-demo ubuntu@<host> 'tmux ls; pgrep -ax ph'          # sessions + proc
ssh -i ~/.ssh/zpr-demo ubuntu@<host> 'tmux capture-pane -t node -p | tail -20'  # recent log
```

**Restart / stop** a `ph`:

```bash
./deploy-zpr.sh                                                # re-deploy + restart both
ssh -i ~/.ssh/zpr-demo ubuntu@<host> 'tmux kill-session -t node'   # stop one
```

**Layout on each host:** `~/zpr/ph`, the one `*.toml` config for that role, and
an `include/` dir with only the certs/keys that config references. Runtime dir
`/var/run/zpr` is created ubuntu-writable (one `sudo` per host, done by the
script). Note `/var/run` is tmpfs — re-run the script after a host reboot.

**Expected state:** the node's `ph` listens on `0.0.0.0:5000`; the web adapter
connects to it and verifies its name over noise. The adapter's link then cycles
in `Helloing`, because it needs the **visa service** — which lives in the local
docker env behind `node1`, and node0 ↔ node1 linking is not implemented yet. So
`Helloing` is the expected steady state for the OCI side today.

### Full startup sequence (both envs)

**Not achievable yet** — `node0 ↔ node1` linking is unimplemented, so the visa
service (local, behind `node1`) is unreachable from OCI and every OCI adapter
cycles in `Helloing`. Starting the docker env first does not change that. The
intended sequence, once the node link works:

1. **Local docker env** — `./local-compute/deploy-docker.sh` already does this
   order: `node1` → `vs` → vs adapter → `web1` adapter.
2. **OCI env** — `node0` first.
3. **Wait for `node1` to connect to `node0`.** ⚠️ Unimplemented: we don't yet
   know what that connection looks like from node0's side, so there's nothing
   to poll for. `deploy-zpr.sh` currently barrels straight past this point.
4. **Then** the `web0` adapter, **then** the `admin` adapter — the order
   `deploy-zpr.sh` already uses.

So only step 3 is missing. When the node link lands, add the wait there (see the
marker in `oci-compute/deploy-zpr.sh`) and the rest of the sequence is in place.

### The `admin` host

The hypothetical admin user's workstation (CN `admin.demo`). Its adapter config
[`adapter-admin-conf.toml.template`](zpr-conf/confs/adapter-admin-conf.toml.template)
sets **no** `zpr_addr`/`tun_if` — the address is assigned dynamically by the
visa service, so `ph` creates its own TUN device and therefore runs under
`sudo`. Everything else matches the other hosts: `~/zpr/{ph,adapter-admin-conf.toml,include/}`,
tmux session `adapter`, log tee'd to `~/zpr/adapter.log`.

**SSH in and curl through ZPR** — needs the adapter running *and* a reachable
visa service, so this does not work yet (see **Current limitation** below):

```bash
ssh -i ~/.ssh/zpr-demo ubuntu@$(tofu -chdir=oci-compute output -json public_ips | jq -r .admin)

curl -v http://[fd5a:5052:8888::8]/     # OciWeb  (webserver in OCI)
curl -v http://[fd5a:5052:8888::9]/     # PremWeb (web1 in the local docker env)
```

Those are the `zpr.addr`s the policy declares for the two services — see
`zpr-conf/admin/multinode-demo.zplc.template`. A curl that hangs or is refused
usually means "no visa", not "no route": check the adapter's output.

Per `zpr-conf/admin/attrfile.json`, `admin.demo` holds `oci_user` but **not**
`prem_user` — so the `OciWeb` curl should succeed and the `PremWeb` one should be
denied. Flip that live by editing the mounted copy and flushing the `attrfile`
service (see the local-docker section below).

**Monitor the admin adapter:**

```bash
A=$(tofu -chdir=oci-compute output -json public_ips | jq -r .admin)

ssh -i ~/.ssh/zpr-demo -t ubuntu@$A tmux attach -t adapter   # live, Ctrl-b d to detach
ssh -i ~/.ssh/zpr-demo ubuntu@$A 'tail -f ~/zpr/adapter.log' # follow the log
ssh -i ~/.ssh/zpr-demo ubuntu@$A 'tmux ls; pgrep -ax ph'     # is it up?
ssh -i ~/.ssh/zpr-demo ubuntu@$A 'ip -br addr'               # the TUN ph created + its ZPR addr
```

Restart it with `./deploy-zpr.sh`, or stop it with `sudo pkill -x ph` (plain
`tmux kill-session` is not enough — `ph` is root here, so tmux running as
`ubuntu` cannot signal it).

The `curl`s above will work once node-to-node linking lands — see
[Full startup sequence](#full-startup-sequence-both-envs) above.



## How to deploy & run ZPR (local docker env)

The local "on-prem" side runs three containers — `node1`, `vs` (visa service),
`web1` — from one image (`zpr-multinode`). `docker-compose.yml` owns the infra
(static IPs on bridge `zpr-local` `172.30.0.0/24`, `node1` publishing `5000`
tcp+udp, tun9 caps); `local-compute/deploy-docker.sh` does the dynamic parts
(render configs, generate `vs_keys.toml`, compile the policy, launch the ZPR
processes in order). See [`work/docker-configure-run-zpr.md`](work/docker-configure-run-zpr.md).

**Prerequisites:** `../oci-compute` applied (the policy needs node0's public IP),
and the image built once:

```bash
docker build -t zpr-multinode .
```

**Deploy:**

```bash
./local-compute/deploy-docker.sh                    # same-host operator
NODE1_EXT_ADDR=<host-ip> ./local-compute/deploy-docker.sh   # cross-host operator
```

Re-runnable: it re-renders configs, recompiles the policy, and restarts each
process (old tmux session killed first). No image rebuild needed for a re-deploy
(configs come in as volume mounts).

**Watch the ZPR processes** (logs tee'd to a host-mounted volume — no `docker
exec` needed):

```bash
tail -f local-compute/logs/*.log
```

Sessions: `node1` (node), `vs` + `vs-adapter` (vs container), `web1-adapter`
(web1). Attach live (Ctrl-b d to detach):

```bash
docker exec -it vs tmux attach -t vs
```

**Expected state:** node1's `ph` listens on `0.0.0.0:5000`; the vs and web1
adapters connect, authenticate, and their `dock link` becomes `ACTIVE` (past
`Helloing`). `cert failed signature verification` / `unverified name` warnings
are benign (default trusted service, cert checking disabled in this demo policy).

**Operator client:** `deploy-docker.sh` renders the host-side client adapter and
generates its key at `local-compute/client/` (`adapter-client-conf.toml` +
`client.key`) — run `sudo bin/ph adapter -c adapter-client-conf.toml` from there
to reach the ZPR web services.

**Administer the visa service (`vs-admin` GUI):** the vsapi access key that
`vs-admin` needs is the same `client.key` generated each deploy at
`local-compute/client/client.key` (host side). `vs-admin` is baked into the image,
so launch it from a terminal attached to the `vs` container, passing the key via
`VS_API_KEY` (no need to copy the file in). The admin API listens on the vs ZPR
address `[fd5a:5052::1]:8182` and presents a self-signed TLS cert, so `--ca-cert`
points at that same cert:

```bash
docker exec -e VS_API_KEY="$(cat local-compute/client/client.key)" -it vs \
  /app/bin/vs-admin \
    --svc-url "https://[fd5a:5052::1]:8182" \
    --ca-cert /conf/include/admin-tls-cert.pem \
    gui
```

Drop `gui` for one-shot commands (e.g. `services`, `policies`, `actors`, `visas`).
`commands/demo-vs-admin` wraps all of this — `commands/demo-vs-admin-gui`, or
`commands/demo-vs-admin actors`.

For watching the service, prefer `commands/demo-zpr-dashboard`: the `zpr-dashboard`
TUI (built from `zpr-visaservice/zpr-dashboard`) is a richer view of the same admin
API. It also runs inside `vs`, with cwd `/conf` — it has no flags and reads
`./config.toml`, which `deploy-docker.sh` installs there from
`zpr-conf/confs/zpr-dashboard-config.toml`. The API key goes in as `ZPR_API_KEY`,
which overrides the file.

**Editing the attribute file (`attrfile.json`) live:** `zpr-conf/admin/attrfile.json`
holds the JSON attributes referenced by the policy and read by the visa service.
`deploy-docker.sh` copies it to `local-compute/conf/vs/attrfile.json`, which is
bind-mounted into the `vs` container at `/conf/attrfile.json` (same dir as
`vs_keys.toml`). To change attributes mid-demo, edit the mounted copy on the host
and tell the visa service to reload it:

```bash
$EDITOR local-compute/conf/vs/attrfile.json          # live copy, no restart needed

docker exec -e VS_API_KEY="$(cat local-compute/client/client.key)" -it vs \
  /app/bin/vs-admin \
    --svc-url "https://[fd5a:5052::1]:8182" \
    --ca-cert /conf/include/admin-tls-cert.pem \
    services -i attrfile --flush
```

`local-compute/conf/` is regenerated on every deploy, so copy the edit back into
`zpr-conf/admin/attrfile.json` to keep it.

`commands/demo-attr` does all of the above in one step — edit, flush, and
`demo-attr save` for the copy-back:

```bash
commands/demo-attr show                        # the live file
commands/demo-attr del admin.demo oci_user     # edit + flush
commands/demo-attr save                        # keep it across the next deploy
commands/demo-attr push                        # or throw it away, back to the baseline
```

**Updating the policy** (edited `zpr-conf/admin/multinode-demo.zpl` or
`multinode-demo.zplc.template`): just re-run `./local-compute/deploy-docker.sh`.
It recompiles the policy to `multinode-demo.bin2` and restarts `vs` with
`--clear-state`, which loads the new policy. No image rebuild needed. (The
containers, tun9, and valkey stay up; only the ZPR processes are relaunched.)

**Updating a binary** (new `ph`/`vs`/etc. in `bin/`): binaries are **baked into
the image**, not mounted, so rebuild the image first, then re-deploy:

```bash
docker build -t zpr-multinode .        # picks up the new bin/
./local-compute/deploy-docker.sh       # `up -d` recreates containers on the new image, relaunches ZPR
```

**Teardown:** `docker compose down`.
