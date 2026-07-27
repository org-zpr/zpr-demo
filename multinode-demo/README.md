# Multinode Demo

## Contents

- `bin` - Binaries to run for the demo
- `local-compute` - Setup code for the local ("on prem") containers.
- `oci-compute` - OpenTofu setup for the remote (OCI cloud) instances.
- `zpr-conf` - All the ZPR config files, certificates, policy, etc.

## How to install (OCI hosts)

Brings up two Ubuntu 24.04 instances (`webserver`, `node`) in OCI —
SSH-reachable, able to reach each other by private IP, with a `tun9` interface,
and nginx on the webserver. No ZPR components yet.

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
ip addr show tun9                       # role's fd5a:... address, state UP
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
on both hosts, injects the node's private IP into the web adapter config, and
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

**Watch a `ph` process** (session name = role; Ctrl-b d to detach):

```bash
ssh -i ~/.ssh/zpr-demo -t ubuntu@<node_public_ip> tmux attach -t node
ssh -i ~/.ssh/zpr-demo -t ubuntu@<web_public_ip>  tmux attach -t adapter
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
connects to it and verifies its name over noise. The adapter's link then times
out in `Helloing` until the **visa service** is up — that runs in the local
docker env (not the OCI hosts), so this is expected for the OCI-only setup.



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
