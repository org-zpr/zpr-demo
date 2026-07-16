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
[`tf-configure-run-zpr.md`](tf-configure-run-zpr.md) for the design.

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

