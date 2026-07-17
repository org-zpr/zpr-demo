# Implementation Steps: docker-configure-run-zpr (PLAN.md §5–8)

Ordered build sequence for the local docker env. Derived from
`docker-configure-run-zpr.md`. Each step is independently verifiable; do them
in order — later steps assume earlier artifacts exist.

Reference implementations to copy from, not reinvent:
- `../containerized-demo/docker/` — Dockerfile (valkey from source), compose,
  entrypoints (tun9 setup).
- `oci-compute/deploy-zpr.sh` — `render()`, `deploy_host()`, `start_ph()` idioms.

All new files live under `multinode-demo/` (compose + Dockerfile) and
`multinode-demo/local-compute/` (deploy script, entrypoints, web1 index, logs/).

---

## Step 1 — Dockerfile (one image, all three containers) — DONE

Base `../containerized-demo/docker/Dockerfile`. Ubuntu 24.04 +
`tmux nginx iproute2 ca-certificates libpcap-dev` + valkey from source (7.2.x,
same ARG build — not in 24.04 repos). `COPY bin/ /app/bin/` to bake in the
`ph`/`vs`/`vsapikey`/`zplc` binaries. `WORKDIR /app`.

- Skipped: multi-stage / binary-stripping. Binaries are baked; local only, no
  registry push (per plan). `ponytail:` add only if image size bites.
- **Verify:** `docker build -t zpr-multinode .` succeeds; `docker run --rm
  zpr-multinode /app/bin/ph --help` and `valkey-server --version` both run.

## Step 2 — web1 index file — DONE

`local-compute/web1-index.html` (or `.txt`): plain text containing
`hello from on-prem`. Mounted over nginx's default root in Step 4.

- **Verify:** file exists, contains the string. (Real check is Step 6 curl.)

## Step 3 — Entrypoints (thin: tun9 + one service each) — DONE

Three scripts under `local-compute/` (mirror `docker-node`/`docker-vs`
entrypoints). Each brings up `tun9` then execs/backgrounds its service. ZPR
`ph`/`vs` launches are **not** here — the deploy script does those via
`docker exec` (so logs tee to the mounted volume). Entrypoints must stay up
(e.g. `sleep infinity` / `tail -f`) so the container lives.

- `entrypoint-node1.sh` — create tun9 (`ip tuntap add … mode tun multi_queue`,
  mtu 1400, addr, up); then idle.
- `entrypoint-vs.sh` — tun9; `valkey-server --bind 127.0.0.1 --port 6379 &`;
  then idle.
- `entrypoint-web1.sh` — tun9; `nginx -g 'daemon off;'` (or start + idle).
- **Verify:** `docker compose up -d` (after Step 4); `docker exec node1 ip addr
  show tun9` shows the device on each container; `docker exec vs redis-cli -p
  6379 ping` → PONG; `docker exec web1 curl -fsS localhost:80` shows the index.

## Step 4 — docker-compose.yml (declarative infra) — DONE

Base `../containerized-demo/docker/docker-compose.yml`. Three services
`node1`/`vs`/`web1`, all `image: zpr-multinode`, each with `cap_add:
NET_ADMIN`, `devices: /dev/net/tun`, `privileged: true`, distinct entrypoint.

- User-defined bridge `zpr-local`, subnet `172.30.0.0/24`, **static IPs**
  (`node1` = `172.30.0.10`, `vs` = `.11`, `web1` = `.12` — node1's must be
  stable, it's baked into adapter configs).
- `node1` publishes `5000:5000/tcp` **and** `5000:5000/udp`.
- Mounts (host → container): rendered configs + referenced `include/` +
  `logs/`; `vs` also gets `vs_keys.toml` + `multinode-demo.bin2`; `web1` gets
  the index file. Mount a scratch conf dir the deploy script fills in Step 5.
- **Verify:** `docker compose config` parses; `docker compose up -d` starts all
  three; `docker network inspect zpr-local` shows the three static IPs.

## Step 5 — local-compute/deploy-docker.sh (imperative host-side) — DONE

Mirror `deploy-zpr.sh` structure (`set -euo pipefail`, scratch dir + trap,
copy its `render()` verbatim — sed + fail-loud on leftover `@@…@@`). Extend
`render()` to substitute all three tokens: `@@NODE1_ADDR@@` (compose static IP,
constant `172.30.0.10`), `@@NODE1_EXT_ADDR@@` (env, default `127.0.0.1`),
`@@NODE0_PUBLIC_ADDR@@` (from OCI tofu state).

Ordered actions inside the script:

1. **Addresses.** `NODE1_ADDR=172.30.0.10` (const); `NODE1_EXT_ADDR` from env
   (default `127.0.0.1`); `NODE0_PUB=$(tofu -chdir=../oci-compute output -json
   public_ips | jq -r .node)`. Fail loud if the tofu output is empty/missing.
2. **Render** every `*.template` → scratch conf dir:
   `adapter-vs`, `adapter-web1` (`@@NODE1_ADDR@@`), `adapter-client`
   (`@@NODE1_EXT_ADDR@@`, → host, next to `client.key`), `node1-conf.toml`
   (no sentinel, copy as-is), `multinode-demo.zplc.template`
   (`@@NODE0_PUBLIC_ADDR@@` + `@@NODE1_EXT_ADDR@@`).
3. **vs_keys.toml + client.key** (§7.3):
   `bin/vsapikey create --init readwrite client <scratch>/vs_keys.toml >
   <host>/client.key`. Keep `client.key` on host; print its path.
4. **Compile policy on host:** `bin/zplc --config <scratch>/multinode-demo.zplc
   zpr-conf/admin/multinode-demo.zpl` → `multinode-demo.bin2` into the vs mount
   dir. (Runs on host: needs `zplc` + `include/` keys the `.zplc` references.)
5. **`docker compose up -d`** — entrypoints bring up tun9 / valkey / nginx.
6. **Launch ZPR in §8 order** via `docker exec` into detached tmux, `tee
   /logs/$name.log` (adapt `start_ph()`):
   1. `node1`: `ph node -c node1-conf.toml` → wait a few s.
   2. `vs`: `vs --clear-state multinode-demo.bin2`.
   3. `vs`: `ph adapter -c adapter-vs-conf.toml`.
   4. sleep 6.
   5. verify nginx serving in `web1`, then `ph adapter -c adapter-web1-conf.toml`.
7. Print operator hints: `client.key` path, `tail -f local-compute/logs/*.log`,
   `docker exec -it <c> tmux attach`.

- Re-runnable: kill old tmux sessions before relaunch (as `start_ph` does);
  re-render + recompile every run.
- **Verify:** run against a live `../oci-compute` apply; script exits 0; all
  five tmux sessions report running.

## Step 6 — End-to-end verify (the plan's "Verify" section) — DONE

1. `local-compute/deploy-docker.sh`.
2. `tail -f local-compute/logs/*.log` → node1 up, vs connected, adapters past
   `Helloing`.
3. From host: curl the ZPR web service through the rendered
   `adapter-client-conf.toml` + `client.key`.
4. If OCI node0 reachable: confirm the OCI↔on-prem link.

**Verified 2026-07-17:** deploy ran clean; all five sessions up; both adapters'
`dock link` reached `ACTIVE` (past `Helloing`); vs authenticated node1 + both
adapters; node1 topology includes the OCI node0 link (`129.213.81.192:5000`).
Item 3 (host client curl) needs `tun9` on the host + a running client `ph` — a
manual operator step; the rendered client config + key are left at
`local-compute/client/`.

## Step 7 — README section — DONE

Add a "local docker env" runbook mirroring the OCI one in
`tf-configure-run-zpr.md`: prerequisites (image built, `../oci-compute`
applied), `deploy-docker.sh` invocation + `NODE1_EXT_ADDR` override, log
tailing, tmux attach, teardown (`docker compose down`).

---

### Dependency graph
```
1 Dockerfile ─┐
2 web1 index ─┼─→ 4 compose ─→ 5 deploy-docker.sh ─→ 6 e2e verify ─→ 7 README
3 entrypoints ┘        (5 also needs live ../oci-compute apply for node0 pub IP)
```
Steps 1–3 are independent and can be built in parallel; 4 needs all three.
