# Plan: Configure & Run ZPR in the local docker env (PLAN.md §5–8)

Stands up the three "on-prem" containers (`node1`, `vs`, `web1`), wires their
ZPR configs with the right addresses, and starts everything in order. The local
counterpart of `tf-configure-run-zpr.md` (OCI side).

## Compose alone? A script alone? No — both.

The OCI side is a pure post-apply script because tofu already owned the infra.
Here the trade-off is reversed for the *static* parts and the same for the
*dynamic* parts, so we split:

- **`docker-compose.yml` owns the declarative infra** — containers, the
  user-defined bridge + static IPs, published ports (`node1` `5000/tcp` +
  `5000/udp`), the tun9 capabilities (`NET_ADMIN`, `/dev/net/tun`, privileged),
  and the volume mounts. Compose expresses all of this natively; a `docker run`
  script would re-implement it by hand. This reuses `containerized-demo/docker`.
- **`local-compute/deploy-docker.sh` owns the dynamic, imperative parts** that
  don't fit compose build/entrypoint time: rendering `@@…@@` templates from
  addresses only known at deploy time (including one pulled from the OCI tofu
  state), generating `vs_keys.toml`, compiling the policy, and launching the ZPR
  processes in the required order. Mirrors `deploy-zpr.sh`.

Entrypoints stay thin: bring up `tun9`, start `valkey` (vs), start `nginx`
(web1). The ZPR process launches are done by the script via `docker exec` so
their logs `tee` to a host-visible volume (see Logging).

## Image

One image, reused by all three containers (like `containerized-demo`):
Ubuntu 24.04 + `tmux` + `nginx` + `valkey` + the `bin/` binaries baked in.
Binaries are large (`ph` ~200 MB, `vs` ~220 MB) but this is local — no network
push, so baking them in is fine and keeps re-deploys volume-only (no rebuild).

Valkey: `apt-get install valkey-server` is not in 24.04's default repos — reuse
`containerized-demo/docker/Dockerfile`'s from-source build unless a packaged
option is confirmed.

## Address model — the crux

See the table in PLAN.md §7. The three substituted values and their sources:

| sentinel | value | source |
|---|---|---|
| `@@NODE1_ADDR@@` | node1 docker-internal static IP | compose (`zpr-local` subnet) |
| `@@NODE1_EXT_ADDR@@` | host IP + `:5000` (node1 from outside docker) | `NODE1_EXT_ADDR` env, default `127.0.0.1` |
| `@@NODE0_PUBLIC_ADDR@@` (policy only) | OCI node0 **public** IP | `tofu -chdir=../oci-compute output -json public_ips \| jq -r .node` |

The policy's `@@NODE0_PUBLIC_ADDR@@` (node0 **public**) is a distinct token from
the OCI `adapter-web0` template's `@@NODE0_ADDR@@` (node0 **private**) — same
host, different addresses, kept separate on purpose.

Files and where each renders / lands:
- `adapter-vs-conf`, `adapter-web1-conf` → `@@NODE1_ADDR@@` → mounted into `vs`
  / `web1`.
- `node1-conf.toml` → no sentinel (`self_addr = 0.0.0.0:5000`) → mounted as-is.
- `multinode-demo.zplc.template` → `@@NODE0_PUBLIC_ADDR@@` + `@@NODE1_EXT_ADDR@@`
  → compiled on host → `multinode-demo.bin2` mounted into `vs`.
- `adapter-client-conf.toml.template` → `@@NODE1_EXT_ADDR@@` → stays on **host**
  (operator's client; not a container), next to `client.key`.

## `local-compute/deploy-docker.sh` — step outline (TODO)

Reuse `deploy-zpr.sh`'s `render()` (sed + fail-on-leftover-`@@…@@`) verbatim.

0. Read `NODE0_PUB` from `../oci-compute` tofu output; take `NODE1_EXT_ADDR`
   from env (default `127.0.0.1`); node1's internal IP is a constant from compose.
1. Render all `*.template` → a scratch conf dir (mounted at deploy).
2. `vsapikey create --init readwrite client .../vs_keys.toml > .../client.key`
   (per PLAN.md §7.3); keep `client.key` on host, tell the operator its path.
3. Compile policy on host: `bin/zplc --config .../multinode-demo.zplc
   .../multinode-demo.zpl` → `multinode-demo.bin2`.
4. `docker compose up -d` (entrypoints: tun9 / valkey / nginx).
5. Launch ZPR processes in §8 order via `docker exec` into detached tmux with
   `tee /logs/$name.log` (mirror `start_ph()`): node1 ph → vs → vs adapter →
   (6 s) → web1 adapter. Verify nginx serving before the web1 adapter.

## Layout & logging

- Mounts per container: rendered config(s) + `include/` (only the referenced
  files) + a shared `logs/` dir; `vs` also gets `vs_keys.toml` +
  `multinode-demo.bin2`.
- Logs: `tail -f local-compute/logs/*.log` on the host (node1, vs, adapters) —
  no `docker exec` needed. Also attach live: `docker exec -it <c> tmux attach`.

## Checklist

- [x] Dockerfile (image with binaries + valkey + nginx + tmux)
- [x] `docker-compose.yml` (network, static IPs, ports, tun caps, mounts)
- [x] per-container entrypoints (tun9 / valkey / nginx)
- [x] `local-compute/deploy-docker.sh` (steps 0–5 above)
- [x] web1 index file ("hello from on-prem")
- [x] README section (mirror the OCI runbook)

## Verify (once implemented)

`deploy-docker.sh` → `tail -f local-compute/logs/*.log` (node1 up, vs connected,
adapters past `Helloing`) → from the host, curl the ZPR web service through the
rendered client adapter → confirm the OCI↔on-prem link if node0 is reachable.
