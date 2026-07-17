# Plan: Configure & Run ZPR on the OCI hosts (PLAN.md §3 + §4)

Covers getting the ZPR binaries + configs onto the `webserver` and `node`
hosts, injecting the OCI-assigned addresses, and starting things in the right
order.

## Can OpenTofu do this alone? No — use a post-apply script.

The address we need to inject (`node`'s private IP) *is* a tofu-known attribute
after apply (`oci_core_instance.host["node"].private_ip`), so in principle tofu
could `templatefile` it into the configs. But tofu is the wrong tool for the
rest of this, for four reasons:

1. **Binaries are ~200 MB each.** They can't ride in cloud-init `user_data`
   (16 KB limit). iot-demo solved this with an `objectstorage.tf` +
   download-in-cloud-init dance — extra machinery we don't need for two hosts.
   `scp` from a script is simpler.
2. **Cross-host ordering.** `webserver`'s adapter config needs `node`'s private
   IP. With `for_each` the two instances are created in parallel; feeding one
   instance's computed attribute into the other's cloud-init means breaking the
   `for_each` and adding explicit `depends_on` — awkward for no gain.
3. **Provisioners are a known anti-pattern.** `file`/`remote-exec` run
   once at create time, aren't tracked in state, and don't re-run on config
   changes. Re-injecting an address after a stop/start would mean tainting the
   instance.
4. **Startup order is imperative** (§4: node up before the web adapter). That's
   a sequence of actions, not desired state — outside tofu's model.

So: **tofu stands up the infra (done); a post-apply bash script does §3 + §4.**
This mirrors iot-demo's `post-init.sh` / `lib.sh` pattern — but *simpler*,
because our injected address comes straight from `tofu output` and doesn't need
the runtime journal-scraping iot-demo used for ZPR-granted dynamic addresses.

## What tofu / cloud-init already covers

- Both hosts up, SSH-able, intra-VCN IP connectivity, `node` open on 5000 (§1).
- `tmux` on both; `nginx` + `/var/www/html/index.html` on `webserver` (§2).
- Static `tun9` address via `zpr-tun.service` on both (§4 steps 1 & 3 —
  "ensure ZPR TUN address is configured" is a no-op; just verify it's up).

Nothing in tofu changes for this work.

## The script: `oci-compute/deploy-zpr.sh` — DONE

**Implemented** as a single self-contained script (no `lib.sh` needed at two
hosts). Run after `tofu apply` from anywhere: `./deploy-zpr.sh`. Structure
borrowed from iot-demo but trimmed.

### Step 0 — read addresses from tofu — DONE

```sh
NODE_PRIV=$(tofu output -json private_ips | jq -r .node)   # e.g. 10.0.0.x
NODE_ADDR="${NODE_PRIV}:5000"
# public IPs (from ssh_commands / public_ips) for the scp/ssh targets
```

Only the **web adapter's `node_addr`** needs injection (`= NODE_ADDR`). The
node's `self_addr` is hardcoded to `0.0.0.0:5000` directly in `node0-conf.toml`
— no templating needed there.

### Step 1 — render config (address injection, §3) — DONE

`node0-conf.toml` ships ready (`self_addr = "0.0.0.0:5000"`, checked in) — copy
it as-is. Configs needing injection carry a `.template` suffix (today just
`adapter-web0-conf.toml.template`) and a sentinel, so injection is a dumb string
swap (no comment-matching, no templating engine):

```toml
node_addr = "@@NODE0_ADDR@@:5000"
```

```sh
# render every *.toml.template -> *.toml in a scratch dir
sed "s/@@NODE0_ADDR@@/${NODE_PRIV}/" adapter-web0-conf.toml.template > "$SCRATCH/adapter-web0-conf.toml"

# REQUIRED: fail loud if any sentinel went unresolved — sed leaves unknown
# @@TOKEN@@s in place silently, and a half-rendered config must never ship.
if grep -n '@@[A-Z0-9_]*@@' "$SCRATCH/adapter-web0-conf.toml"; then
  echo "ERROR: unresolved template token(s) above in adapter-web0-conf.toml" >&2
  exit 1
fi
```

The `.template` suffix is the marker for "needs rendering" — the script renders
each `*.toml.template` into the scratch dir and copies plain `*.toml` as-is.
Keeps the checked-in template out of the way of anything expecting valid TOML.

**Requirement:** rendering MUST error out if a template still contains an
unresolved `@@TOKEN@@` after substitution. The `grep`-and-`exit 1` above is that
gate — no host ever receives a half-rendered config.

### Step 2 — deploy files to each host (§3) — DONE

Layout on host (`ph` looks for `include/` relative to the config, per §3).
Everything runs as `ubuntu` — no root needed for `ph` itself:

```
~/zpr/               # /home/ubuntu/zpr, owned by ubuntu
  ph
  <the one conf for this host>.toml
  include/           # ONLY the files this host's config references
```

Copy only the include files the config actually references — derive the list
from the config itself so it stays correct as configs change:

```sh
mapfile -t inc < <(grep -oE 'include/[^"]+' "$CONF" | sort -u)
scp bin/ph "$CONF" "${inc[@]/#/zpr-conf/}" ubuntu@$HOST:zpr/   # then arrange include/ on host
```

The two hosts' reference sets today (informational — the grep is the source of truth):
- `node` (`node0-conf.toml`): `auth-ca.crt`, `node0-noise.crt`,
  `node0-noise.key`, `node0-private-key.pem`
- `webserver` (`adapter-web0-conf.toml`): `auth-ca.crt`, `node0-noise-pub.pem`,
  `web0-private-key.pem`

(Only `ph` is needed on OCI. `vs`, `vs-admin`, `zplc`, etc. are for the docker
`vs` container in §6 — not deployed here.)

### Step 3 — start in order (§4), in a tmux session — DONE

`ph` needs a runtime dir `/var/run/zpr` that's writable by the user running it
(ubuntu). `/var/run/zpr` needs root to create, so this is the one `sudo` step,
done once per host before starting `ph`:

```sh
sudo install -d -o ubuntu -g ubuntu /var/run/zpr
```

(`/var/run` is a tmpfs, so this doesn't survive reboot — re-run it, or drop a
tmpfiles.d snippet if boot-persistence matters. ponytail: inline for now.)

`ph` logs to stdout. Start each in a detached `tmux` session (session name =
mode, one `ph` per host) so you can ssh in and attach to watch it live:

```sh
# on node (step 2): start the node first
tmux kill-session -t node 2>/dev/null || true
tmux new-session -d -s node -c ~/zpr './ph node -c ~/zpr/node0-conf.toml'

# nginx already running from cloud-init (step 4 = no-op, just verify curl :80)

# on webserver (step 5): start the adapter, pointed at the now-up node
tmux kill-session -t adapter 2>/dev/null || true
tmux new-session -d -s adapter -c ~/zpr './ph adapter -c ~/zpr/adapter-web0-conf.toml'
```

Watch output: `ssh -i <key> -t ubuntu@<host> tmux attach -t node`
(Ctrl-b d to detach). tmux is already installed by cloud-init (§2).

<!-- ponytail: tmux, not systemd. Upgrade to a systemd unit only if we want
     restart-on-boot or `journalctl` — see iot-demo's unit files. -->

## Re-run behaviour

- Idempotent-ish: `scp` overwrites (the ~200 MB `ph` is skipped when the host
  already has a same-size copy); each `ph` is started with `tmux kill-session`
  first so a re-run doesn't stack sessions/processes.
- The injected address is a stable OCI private IP — it only changes if the
  `node` instance is recreated, so a re-run of the whole script after any
  `tofu apply` that touched `node` is the safe move.

## Decided

- **Install dir:** `~/zpr` (ubuntu-owned, no sudo).
- **`ph` runs as ubuntu**, no root.
- **`self_addr`:** hardcoded `0.0.0.0:5000` in `node0-conf.toml` — not templated.
- **Runtime dir:** `/var/run/zpr`, created ubuntu-writable (one `sudo install -d`
  per host before starting `ph`).

## Open questions before implementing

1. **tun9 sanity** — DONE. `check_tun9` runs `ip addr show tun9` on each host at
   the top of the script and fails loud if it's down.

## Status — DONE

`deploy-zpr.sh` implemented and run against the live OCI hosts:

- node: `ph node` up in tmux, dock listening on `0.0.0.0:5000`, CN `node0.demo`.
- webserver: `ph adapter` up in tmux; reaches the node and completes noise name
  verification (`dock link has verified name "node0.demo"`).

The adapter's link then times out in `Helloing` — it needs the visa service
(`fd5a:5052::1`), which lives in the local docker env (§5/§6, not yet deployed).
Everything in scope for §3 + §4 (OCI env) works.

Note: the running `webserver` instance had lost the cloud-init nginx install to
a boot-time DNS race (§2); repaired in place (apt install nginx + `index.html`).
The cloud-init template now retries the install fetch as well as `apt-get update`
(`host.yaml.tftpl`), so fresh boots self-heal — the live host was fixed manually
because cloud-init only runs at first boot.

## Skipped (add when needed)

- Object storage for binaries — `scp` is fine at 2 hosts. Add if hosts multiply.
- systemd units — `nohup` covers the demo. Add for boot-persistence.
- tofu-side config templating — rejected above; keeps apply/config decoupled.
