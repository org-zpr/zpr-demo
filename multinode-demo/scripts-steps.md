# Implementation Steps: helpful scripts

Ordered build sequence for the demo-operator toolkit. Derived from
`scripts-plan.md` — read the name table there first; every step below assumes it.
Each step is independently verifiable; do them in order.

Reference implementations to copy from, not reinvent:
- `../iot-demo/oci-compute/lib.sh` — sourced-lib guard, `SSH_OPTS`, tofu-output idiom.
- `oci-compute/deploy-zpr.sh:71` `start_ph()` — the pkill/kill-session/new-session dance.
- `local-compute/deploy-docker.sh:79` `launch()` — the docker equivalent.
- `~/Downloads/attribute.sh` — jq transforms, `canon()`, selftest, `usage()`.

Everything new lives in `multinode-demo/commands/`. Nothing is generated, so
`.gitignore` needs no change.

Two commits: **Step 1 alone** (changes demo behaviour), then Steps 2–9 (pure addition).

---

## Step 1 — Fix the attrfile baseline — DONE

Independent of the toolkit; do it first so the demo semantics are right before you
build tools that manipulate them.

Presence of a key sets the tag (`prem_user -> #user.prem_user` in
`zpr-conf/admin/multinode-demo.zplc.template`), so `"prem_user": ["no"]` **grants**
`prem_user`. Drop the key entirely from `admin.demo` in
`zpr-conf/admin/attrfile.json`, leaving `oci_user` — which is what `README.md:158-160`
already claims.

- **Verify:** `jq . zpr-conf/admin/attrfile.json` parses; `admin.demo` has exactly one
  key. Full behavioural check (curl to `PremWeb` denied) is Step 9 — it needs the
  node0↔node1 link, still unimplemented.
- **Commit** this on its own.

## Step 2 — `commands/lib.sh` — DONE

The only file with real logic. Sourced, never executed — guard with the
`BASH_SOURCE[0]` check from `../iot-demo/oci-compute/lib.sh:12`.

Contents, in order:
- `MULTI_DIR` from `BASH_SOURCE` (idiom: `deploy-zpr.sh:9`), `KEY`/`SSH_OPTS`
  (`deploy-zpr.sh:15`).
- The six-row name table as parallel associative arrays: `KIND` `TARGET` `SESSION`
  `LOG` `LAUNCH` `SUDO`. Declare `NAMES=(node0 ociweb admin node1 vs premweb)` too —
  `demo-status` and the error path both need the ordered list.
- `resolve NAME` — set `$KIND` etc. for the caller, or print `NAMES` and `exit 2`.
- `oci_ip <tofu-key>` — `tofu -chdir="$MULTI_DIR/oci-compute" output -json public_ips |
  jq -r .<key>`; memoise in a var; empty/`null` ⇒ "is oci-compute applied?"
  (`deploy-docker.sh:33`).
- `on NAME cmd…` / `on_tty NAME cmd…` — the single ssh-vs-docker dispatch point.

- **Verify:** `bash -n commands/lib.sh`; `bash commands/lib.sh` refuses to run
  directly; a throwaway `source commands/lib.sh && resolve vs && echo $SESSION` →
  `vs-adapter`, and `resolve bogus` → six names, exit 2.

## Step 3 — `demo-shell`, `demo-watch-ph`, `demo-check-ph` — DONE

Three thin wrappers over Step 2. Each is `source lib.sh; resolve "$1"; on…`.

- `demo-shell NAME` → `on_tty NAME bash -l`.
- `demo-watch-ph NAME [-a]` → default `tail -f` the log (host-side file for docker
  names, `on NAME tail -f ~/zpr/…` for oci); `-a` → `on_tty NAME tmux attach -t
  $SESSION`.
- `demo-check-ph NAME` → `pgrep -x ph` on the target, then `tail -10` of the log.
  `ph is up (NAME)` / `ph is DOWN (NAME)`; **exit 1 when down**.

- **Verify:** `bash -n`; with infra up, `demo-check-ph node0; echo $?` → 0, and after
  `demo-shell node0` + `tmux kill-session -t node`, → `DOWN` / 1.

## Step 4 — `demo-restart-ph` — DONE

The one wrapper that isn't trivial. Emit, for the resolved name:

```
<sudo?>pkill -x ph ; tmux kill-session -t $SESSION ; \
tmux new-session -d -s $SESSION -c <wd> '<LAUNCH> 2>&1 | tee <log>' ; \
sleep 1 ; tmux has-session -t $SESSION
```

`pkill` **before** `kill-session` (`deploy-zpr.sh:73-77`: a root `ph` outlives a
session killed by `ubuntu`). Non-zero exit + clear error if `has-session` fails. Add a
`ponytail:` comment naming both duplicated call sites.

- **Verify:** `demo-restart-ph node0` → back up per `demo-check-ph`. Then the root case:
  `demo-restart-ph admin`, and `demo-shell admin` + `pgrep -ax ph` shows exactly one
  pid, newer than before.

## Step 5 — `demo-status` — DONE

Loop `NAMES` calling `demo-check-ph`, `|| true` so one failure doesn't abort the sweep.

- **Verify:** six blocks, all `ph is up`, exit 0 with infra healthy.

## Step 6 — `demo-watch-vs` — DONE

`tail -f "$MULTI_DIR/local-compute/logs/vs.log"`. The visa service, not its adapter.

- **Verify:** streams, and is a *different* log from `demo-watch-ph vs`.

## Step 7 — `demo-vs-admin` + `demo-vs-admin-gui` — DONE

`demo-vs-admin` is the `README.md:242` invocation with `"$@"` on the end. Guard on
`local-compute/client/client.key` missing → "run local-compute/deploy-docker.sh first".
`demo-vs-admin-gui` is `exec "$(dirname "$0")/demo-vs-admin" gui`.

- **Verify:** `demo-vs-admin services` lists services (`attrfile`, `default`);
  `demo-vs-admin-gui` opens the GUI; with `client.key` moved aside, the guard fires.

## Step 8 — `demo-attr` — DONE

Port `~/Downloads/attribute.sh`. Keep verbatim: `jq_set`, `jq_del`, `canon()`, the
unknown-actor check with the "known: …" hint, the no-change short-circuit, `usage()`.

Changes:
- `LIVE="$MULTI_DIR/local-compute/conf/vs/attrfile.json"`, `BASE="$MULTI_DIR/zpr-conf/admin/attrfile.json"`.
  `read_remote`/`write_remote` collapse to `cat`/`>` — it's a bind mount. Drop the
  SSH-atomicity `ponytail:` note with the SSH.
- `flush()` → `demo-vs-admin services -i attrfile --flush`, still after the write.
- Add `save` (live → `BASE`); `push` (`BASE` → live + flush) already exists.
- Rewrite the selftest fixtures to `user.demo`/`admin.demo` × `prem_user`/`oci_user`;
  same five assertions.
- Header comment states the tag semantics; `del` names the tag it dropped
  (`-> #user.prem_user`).
- Guard: `LIVE` missing → point at `deploy-docker.sh`.

- **Verify:** `commands/demo-attr selftest` passes offline — this is the toolkit's one
  automated check. Then live: `show`, `del admin.demo oci_user` → updated + flushed,
  re-run → "no change" and **no** flush, `push` restores, `save` survives a
  `deploy-docker.sh`.

## Step 9 — Docs + end-to-end — DONE

- `README.md`: add `commands/` to the contents list at `README.md:5-8`; add a "Handy
  commands" section (table of the ten commands + six NAMEs) noting these wrap the
  long-form incantations already documented — keep those, they're the fallback.
- `AGENTS.md`: add `commands/` and mark this plan done.
- `bash -n commands/*` and `shellcheck commands/*` across the set.
- Error paths: `demo-shell bogus` → six names, exit 2. `demo-shell node0` with
  `oci-compute` destroyed → "is oci-compute applied?", not jq/ssh noise.
- Tag semantics live: `demo-attr set admin.demo prem_user no` then curl `PremWeb` from
  `admin` — still **allowed**. `demo-attr del admin.demo prem_user`, curl again —
  denied. **Blocked on node0↔node1 linking** (`README.md:115-132`); everything else
  above verifies without it.

---

## Notes from the build

- **`vs-admin` exits 0 on HTTP errors.** `demo-attr`'s `flush()` therefore greps the
  output instead of trusting `$?`, and fails loudly — a silent "flushed" that did not
  flush would make the demo lie about policy state. (This is what surfaced the stale
  image below, rather than reporting a flush that never happened.)
- **`deploy-zpr.sh` was not re-runnable across a binary change — fixed.** Its `scp` of
  `ph` hit `ETXTBSY` ("dest open \"zpr/ph\": Failure") because the running `ph` is the
  destination file; `deploy_host()` uploaded before `start_ph()` stopped anything.
  `deploy_host()` now stops `ph` (with `sudo`, covering the root-owned admin host)
  inside the upload branch only, so the common same-size re-run is untouched. Note
  `pkill` alone was not enough: it returns once the signal is *sent*, and scp into a
  still-dying `ph` fails identically — hence the wait-for-exit loop with a `-9`
  fallback.
- `resolve` also derives `N_TLOG`, the log path *as the target sees it*: for docker the
  `tee` must write `/logs/<session>.log` inside the container, not the host-side path
  the tailing commands use.
- All steps verified live against both environments after the 2026-07-29 binary
  refresh (image rebuilt, both deploys re-run): six `ph` up; OCI root and non-root
  restarts; docker restart; down-and-back; `demo-attr` `del`/no-change/`push` each with
  a real flush (`202 Accepted`, "refreshed attrfile; active visas are being
  revalidated"); `demo-vs-admin services` lists `attrfile` as `Trusted("file")`.
- Step 9's last item — the end-to-end `PremWeb` curl from `admin` — remains blocked on
  `node0 ↔ node1` linking, as written. The OCI adapters still cycle: node0 logs
  `Received terminate for link N with reason RequestTimedOut`, so they never reach the
  visa service.
