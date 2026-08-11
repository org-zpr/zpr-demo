# feature: helpful scripts

A set of commands to drive the multinode demo once the infrastructure is up.

## Why

Driving the demo today means hand-typing long incantations copied out of `README.md`:
`tofu output -json public_ips | jq -r .admin`, `ssh -i ~/.ssh/zpr-demo -t ubuntu@$A tmux
attach -t adapter`, a five-line `docker exec -e VS_API_KEY=... vs /app/bin/vs-admin
--svc-url ... --ca-cert ...`. Six ZPR processes across two environments (three OCI
hosts, three docker containers), each reached a different way. Fine for building the
demo, hostile for running one in front of an audience.

Decisions already taken:

- **No `demo-hosts.txt`.** The web-service addresses are hardcoded in policy
  (`fd5a:5052:8888::8` / `::9`), so the operator writes `/etc/hosts` by hand.
  (Superseded: `oci-compute/deploy-zpr.sh` now plants both entries on the admin
  host — see `work/hosts-files.md`.)
- **No generated env file.** `commands/lib.sh` resolves OCI public IPs lazily from
  `tofu output`. Nothing to regenerate after a `tofu apply`, nothing to go stale.
- **`demo-attr`**, not `attribute.sh` — consistent with the other `demo-*` commands.
  All five existing subcommands (`set`/`del`/`show`/`push`/`selftest`) are preserved.

## What exists to build on

| thing | where |
|---|---|
| OCI addresses | `tofu -chdir=oci-compute output -json public_ips` → keys `node`, `webserver`, `admin` |
| OCI ph launch (pkill/kill-session/new-session dance) | `oci-compute/deploy-zpr.sh:71` `start_ph()` |
| docker ph launch | `local-compute/deploy-docker.sh:79` `launch()` |
| `vs-admin` invocation | `README.md:242` (docker exec + `VS_API_KEY` + `--svc-url` + `--ca-cert`) |
| attrfile live copy | `local-compute/conf/vs/attrfile.json` — **bind-mounted** into `vs` at `/conf/attrfile.json` |
| attrfile baseline | `zpr-conf/admin/attrfile.json` |
| jq transforms + selftest to port | `~/Downloads/attribute.sh` |
| sourced-lib pattern to mirror | `../iot-demo/oci-compute/lib.sh` |

Two simplifications fall out of the current design and should be exploited:

- The attrfile is a **host-side bind mount**, so `demo-attr` needs no SSH and no
  `docker exec` for its read/modify/write — unlike the iot-demo version, which did
  `ssh_core "sudo cat ..."` / `sudo tee`. Only the *flush* crosses a boundary.
- ZPR configs on the OCI hosts and in the containers are already in place after a
  deploy, so `demo-restart-ph` only has to relaunch — no rendering, no scp.

## The name table

One identifier set, used by every command. Names match the adapter CNs already in the
policy, so they read the same in `demo-*` output and in `ph` logs.

| NAME | kind | target | tmux session | log | launch command | root? |
|---|---|---|---|---|---|---|
| `node0` | oci | tofu key `node` | `node` | `~/zpr/node.log` | `./ph node -c ~/zpr/node0-conf.toml` | no |
| `ociweb` | oci | tofu key `webserver` | `adapter` | `~/zpr/adapter.log` | `./ph adapter -c ~/zpr/adapter-web0-conf.toml` | no |
| `admin` | oci | tofu key `admin` | `adapter` | `~/zpr/adapter.log` | `./ph adapter -c ~/zpr/adapter-admin-conf.toml` | **yes** (`sudo`) |
| `node1` | docker | container `node1` | `node1` | `local-compute/logs/node1.log` | `/app/bin/ph node -c node1-conf.toml` | n/a |
| `vs` | docker | container `vs` | `vs-adapter` | `local-compute/logs/vs-adapter.log` | `/app/bin/ph adapter -c adapter-vs-conf.toml` | n/a |
| `premweb` | docker | container `web1` | `web1-adapter` | `local-compute/logs/web1-adapter.log` | `/app/bin/ph adapter -c adapter-web1-conf.toml` | n/a |

`vs` means the vs container's **ph adapter**. The visa service process itself
(session `vs`, `logs/vs.log`) is not a `ph` and is served by `demo-watch-vs`.

`admin` runs `ph` as root (dynamic ZPR address ⇒ `ph` creates its own TUN), which is why
restart needs `sudo pkill -x ph` and not just `tmux kill-session` — see the comment at
`deploy-zpr.sh:73-77`.

## Files

All new, all under `multinode-demo/commands/`. Nothing is generated, so nothing is
gitignored — the whole directory is committed.

```
commands/
  lib.sh              # sourced; name table + resolvers + ssh/docker helpers
  demo-shell          # interactive shell on NAME
  demo-watch-ph       # follow NAME's ph log (-a to tmux-attach instead)
  demo-check-ph       # is NAME's ph up? + last 10 log lines; exit 1 if down
  demo-restart-ph     # relaunch NAME's ph
  demo-status         # demo-check-ph across all six, one screen
  demo-watch-vs       # follow the visa service log (not the vs ph log)
  demo-vs-admin       # vs-admin wrapper: fills svc-url, ca-cert, api key
  demo-vs-admin-gui   # one-line alias for `demo-vs-admin gui`
  demo-attr           # attrfile edit + flush (set/del/show/push/selftest/save)
```

### `lib.sh`

Sourced, never executed (guard with the `BASH_SOURCE[0]` check from
`../iot-demo/oci-compute/lib.sh:12`). Provides:

- `MULTI_DIR` — repo `multinode-demo/`, derived from `BASH_SOURCE`, so every command
  works from any cwd (same idiom as `deploy-zpr.sh:9`).
- `KEY="${SSH_KEY:-$HOME/.ssh/zpr-demo}"`, `SSH_OPTS=(...)` — copied from
  `deploy-zpr.sh:15`.
- The name table as parallel associative arrays: `KIND`, `TARGET`, `SESSION`, `LOG`,
  `LAUNCH`, `SUDO`.
- `resolve NAME` — validate; on an unknown name print the six valid names and exit 2.
- `oci_ip <tofu-key>` — `tofu -chdir="$MULTI_DIR/oci-compute" output -json public_ips |
  jq -r .<key>`. Memoised in a shell variable so a command that needs it twice pays
  once. Empty/`null` result ⇒ clear error ("is oci-compute applied?"), mirroring
  `deploy-docker.sh:33`.
- `on NAME <remote-command…>` — the single dispatch point: `ssh "${SSH_OPTS[@]}"
  ubuntu@$(oci_ip …) …` for oci, `docker exec …` for docker. `on_tty NAME …` is the
  `-t` / `-it` variant.

Everything else is a thin wrapper over `on`.

### `demo-shell NAME`

`on_tty NAME bash -l` — oci: an ssh login shell; docker: `docker exec -it <c> bash`
(the image is ubuntu:24.04, bash is present). Lands in `~/zpr` on OCI and `/conf` in
containers.

### `demo-watch-ph NAME [-a]`

**Default is `tail -f` on the log, not `tmux attach`.** Both environments already tee
every `ph` to a file precisely so the tmux session is not the only handle
(`deploy-zpr.sh:80`, `deploy-docker.sh:81`). Tailing is read-only: a reflexive Ctrl-C
scrolls past nothing instead of killing the demo's `ph`. `-a` opts into
`tmux attach -t <session>` when you actually want the pane.

For docker names the log is host-side under `local-compute/logs/`, so watching without
`-a` needs no docker at all — plain `tail -f`.

### `demo-check-ph NAME`

`pgrep -x ph` on the target (`-x`, matching the name not the cmdline — same reasoning as
`deploy-zpr.sh:76`), then `tail -10` of the log. Prints `ph is up (NAME)` /
`ph is DOWN (NAME)` and **exits 1 when down**, so it composes into other scripts.

### `demo-restart-ph NAME`

Replays the launch dance for one name:

```
<sudo?>pkill -x ph ; tmux kill-session -t $SESSION ; tmux new-session -d -s $SESSION -c <wd> '<LAUNCH> 2>&1 | tee <log>'
sleep 1 ; tmux has-session -t $SESSION   # else: error, non-zero exit
```

`pkill` **before** `kill-session` — a root `ph` outlives a session killed by `ubuntu`
(`deploy-zpr.sh:73-77`). `pkill -x ph` is host-wide, which is correct here: one `ph` per
host/container.

> This duplicates ~6 lines of `deploy-zpr.sh:start_ph` and `deploy-docker.sh:launch`.
> Deliberate: factoring a shared launcher out of two working, differently-shaped deploy
> scripts costs more than the duplication. Mark it with a `ponytail:` comment naming
> both call sites so the drift stays visible.

### `demo-status`

`for n in node0 ociweb admin node1 vs premweb; do demo-check-ph "$n"; done`, with
`|| true` so one down process doesn't abort the sweep. Not in the original sketch; four
lines, and it is what you actually want the moment something looks wrong mid-demo.

### `demo-watch-vs`

`tail -f "$MULTI_DIR/local-compute/logs/vs.log"` — the visa service, not its adapter.

### `demo-vs-admin CMD…`

```bash
docker exec -e VS_API_KEY="$(cat "$MULTI_DIR/local-compute/client/client.key")" -it vs \
  /app/bin/vs-admin \
    --svc-url "https://[fd5a:5052::1]:8182" \
    --ca-cert /conf/include/admin-tls-cert.pem \
    "$@"
```

Straight from `README.md:242`. The admin API listens on the vs **ZPR** address, so this
must run inside the container. Guard: if `client.key` is missing, say "run
local-compute/deploy-docker.sh first" rather than letting `cat` fail obscurely.

`vs-admin` also accepts `--api-key-file`, but `client.key` lives on the host and is not
mounted into `vs`, so `-e VS_API_KEY` stays the right channel.

### `demo-vs-admin-gui`

`exec "$(dirname "$0")/demo-vs-admin" gui`. Two lines; kept because it is the
most-typed command in a demo.

### `demo-attr` — all five existing subcommands, plus `save`

Port of `~/Downloads/attribute.sh`. **Every existing feature is preserved**; what
changes is where the file lives and how the flush is issued.

| subcommand | behaviour |
|---|---|
| `set <actor> <attr> <value>` | `.[$a][$k] = [$v]`; adds if absent, replaces if present |
| `del <actor> <attr>` | `del(.[$a][$k])`; actor entry stays as `{}` |
| `show [actor]` | whole file, or one actor entry |
| `push` | overwrite live copy from the baseline `zpr-conf/admin/attrfile.json`, flush |
| `selftest` | offline jq-transform check, no infra needed |
| `save` | **new** — copy live → baseline (see below) |

Kept verbatim from the original: the `jq_set` / `jq_del` transforms, `canon()`
(canonical compare, because the file is hand-formatted), the unknown-actor check with
the "known: …" hint, the "no change ⇒ don't write, don't flush" short-circuit, and the
`usage()` that greps its own header comment.

Changes:

- **Read/write are local.** `LIVE="$MULTI_DIR/local-compute/conf/vs/attrfile.json"` is
  bind-mounted into `vs` at `/conf/attrfile.json`, so `read_remote`/`write_remote`
  collapse to `cat`/`>`. The `ponytail:` note about non-atomic read-modify-write over
  SSH goes away with the SSH.
- **Flush** calls `demo-vs-admin services -i attrfile --flush` instead of the iot-demo's
  `vs-admin.sh`. Order preserved: flush runs after the write, and a failed flush aborts
  under `set -e`.
- **`save`** — `local-compute/conf/` is wiped and regenerated by every
  `deploy-docker.sh` run (`deploy-docker.sh:49`), so a live edit is lost on the next
  deploy. `README.md:269` currently tells the operator to copy it back by hand; `save`
  is that copy. Its inverse, `push`, was already in the original.
- **Selftest fixtures** rewritten to this demo's actors (`user.demo`, `admin.demo`) and
  attributes (`prem_user`, `oci_user`) instead of the iot-demo's `device-a.zpr.org` /
  `OCIApproved`. Same five assertions; it doubles as documentation of the file shape.
- Guard: if `LIVE` is missing, point at `deploy-docker.sh`.

**`del` is the only way to revoke; `set … no` does nothing.** The `.zplc` maps the
attribute to a *tag* — `returns_attributes = ["prem_user -> #user.prem_user", …]` — so
mere **presence** of the key sets the tag, whatever its value. The baseline
`zpr-conf/admin/attrfile.json` therefore already grants `admin.demo` both `prem_user`
and `oci_user`, despite `"prem_user": ["no"]`; that `["no"]` reads as a denial and
isn't one. Two consequences for this work:

- Say so in `demo-attr`'s header comment, and have `del`'s output name the tag it
  dropped (`-> #user.prem_user`), so the operator sees the mechanism mid-demo.
- Fix the baseline: `admin.demo` should have **no** `prem_user` key at all, matching
  what `README.md:158-160` already claims ("holds `oci_user` but **not** `prem_user`").
  A one-line edit to `zpr-conf/admin/attrfile.json`, but it changes demo behaviour —
  the `PremWeb` curl from `admin` is meant to be denied and currently would not be.
  Do it as its own commit, separate from adding `commands/`.

## Docs

Add a short **"Handy commands"** section to `README.md` — a table of the ten commands
and the six NAMEs, plus one line saying the long-form incantations elsewhere in the
README are what these wrap. Do not delete the long forms; they are the reference when a
command misbehaves.

Also add `commands/` to the contents list at `README.md:5-8` and to `AGENTS.md`.

## Verification

1. `commands/demo-attr selftest` — offline, no infra. The one automated check; it pins
   the only non-trivial logic in the toolkit (the jq transforms).
2. `bash -n commands/*`, and `shellcheck commands/*` if available.
3. Infra up (`tofu apply` + `deploy-zpr.sh`, `deploy-docker.sh`), then:
   - `demo-status` — six lines, `ph is up` for all six.
   - `demo-check-ph node0; echo $?` → 0. Stop it (`demo-shell node0`, `tmux kill-session
     -t node`), re-check → `DOWN`, exit 1. `demo-restart-ph node0` → back up.
   - `demo-restart-ph admin` — the root-`ph` case. Confirm the *old* process is gone
     (`demo-shell admin`, `pgrep -ax ph` shows one pid, newer than before).
   - `demo-watch-ph vs` streams; Ctrl-C leaves the process running (`demo-check-ph vs`
     still 0). `demo-watch-ph -a vs` attaches, Ctrl-b d detaches cleanly.
   - `demo-vs-admin services` lists services; `demo-vs-admin-gui` opens the GUI.
   - `demo-attr show` → the two actors. `demo-attr del admin.demo oci_user` → "updated"
     + "flushed". `demo-attr show admin.demo` reflects it. Re-run → "no change", no
     flush. `demo-attr push` restores the baseline. `demo-attr save` after an edit makes
     it survive a `deploy-docker.sh`.
   - Tag semantics: `demo-attr set admin.demo prem_user no` then curl `PremWeb` from
     `admin` — still **allowed**, because presence is what counts. `demo-attr del
     admin.demo prem_user` then curl again — now denied. This is the pair the demo
     should actually run.
4. Unknown-name path: `demo-shell bogus` prints the six valid names, exits 2.
5. OCI-down path: `demo-shell node0` with `oci-compute` destroyed gives the "is
   oci-compute applied?" error, not a jq/ssh stack of noise.

The end-to-end demo story that ties it together — `demo-attr del admin.demo oci_user`,
then `curl http://[fd5a:5052:8888::8]/` from the admin host now denied — needs
`node0 ↔ node1` linking, which is still unimplemented (`README.md:115-132`). Everything
above is verifiable without it.

## Out of scope

- `demo-hosts.txt` (dropped — addresses are static and hand-written).
- Any change to `deploy-zpr.sh` / `deploy-docker.sh`. The commands read the world those
  scripts leave behind; they do not modify them.
- Refactoring the two deploy scripts to share a launcher with `demo-restart-ph`.
- Bash completion for NAMEs.
