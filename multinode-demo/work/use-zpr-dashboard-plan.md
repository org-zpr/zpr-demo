# FEATURE: use new 'zpr-dashboard' tool

The zpr-dashboard is a binary that is an improved version of of running the
`vs-admin` in "gui" mode (see commands/demo-vs-admin-gui).

It brings up a large terminal UI for observing the visa service state.
It needs to run on the same VM/Host as the visa service.

Leave `demo-vs-admin-gui` alone -- we may still want to run that, but we
now want a new command named (for example), `demo-zpr-dashboard` which
will invoke this new tool.

The zpr-dashboard uses some of the same configuration args as vs-admin but it requires
a config file.

- Currently that file must be called 'config.toml' and it must be in the
  directory where you invoke `zpr-dashboard`.

- I have put a static config file named `zpr-dashboard-config.toml` into
  `zpr-conf/confs`.

The `zpr-dashboard` binary is built from the `zpr-visaservice` repo. The
current `Makefile` here that builds the other binaries needs to be updated to
build and copy this.  Something like this should work:

```
cd $ZPR_ROOT/zpr-visaservice/zpr-dashboard && make build
cp $ZPR_ROOT/zpr-visaservice/zpr-dashboard/bin/zpr-dashboard bin/
```

## What the tool actually needs

Read from `$ZPR_ROOT/zpr-visaservice/zpr-dashboard`, and it settles the design:

- It is a **Go** program (bubbletea TUI), not Rust. `make build` → `bin/zpr-dashboard`.
  Go 1.26.5 is installed on this host.
- `internal/config/config.go` `Load()` hard-codes `path := "config.toml"` and **errors
  if the file is missing**, so a `config.toml` has to exist in the cwd — there is no
  flag for it.
- But `setenv()` in that same file **skips any key already present in the real
  environment** ("values already present in the real environment always win over the
  file"). Every setting is overridable with `docker exec -e`.
- `internal/dataplane/client.go` `NewDefault()` reads `ZPR_API_KEY` first and only falls
  back to reading `ZPR_KEY_FILE`. So the API key goes in by env, exactly the way
  `commands/demo-vs-admin` already passes `VS_API_KEY` — **no key file has to enter the
  container.**
- Relative `[files]` paths resolve against `filepath.Dir("config.toml")`, i.e. the cwd.
  Running with cwd `/conf` makes `ca = "include/admin-tls-cert.pem"` resolve to
  `/conf/include/admin-tls-cert.pem`, which `deploy-docker.sh` already places (it copies
  the whole `zpr-conf/include/` into each container's `/conf/include`).

**No changes to `zpr-visaservice` are needed.** Plant the config file where the tool
will look, pass the key by env.

### Where it runs

`vs` is a docker container (`commands/lib.sh`: `KIND[vs]=docker`) and the admin API
listens on `[fd5a:5052::1]:8182` — that is `tun9` *inside* the vs container
(`local-compute/entrypoint-vs.sh`). The host has no route to it, so the dashboard has to
run under `docker exec` in `vs`, same as `demo-vs-admin`. Nothing changes on the OCI
side.

## Implementation Plan

### Step 1 — `zpr-conf/confs/zpr-dashboard-config.toml` — DONE

Comment out what the demo does not use and say why. `[files] key` is dead config:
`demo-zpr-dashboard` supplies `ZPR_API_KEY` by env, so `NewDefault()` never opens a key
file. Keep `base_url`, `timeout`, `ca` and `ui.show_static` live.

Rewrite the header comment to record three things: the file must be named `config.toml`
and sit in the cwd; `deploy-docker.sh` installs it as
`local-compute/conf/vs/config.toml` → `/conf/config.toml` inside `vs`; and any `ZPR_*`
env var set on the process wins over the value here.

### Step 2 — `Makefile`: new `dashboard` target — DONE

A separate target rather than folding it into `visaservice` — different toolchain (`go`,
via the sub-Makefile's own `build` target).

```make
all: ph visaservice compiler dashboard

dashboard: check-zpr-root
	mkdir -p bin
	cd "$(ZPR_ROOT)/zpr-visaservice/zpr-dashboard" && make build
	cp "$(ZPR_ROOT)/zpr-visaservice/zpr-dashboard/bin/zpr-dashboard" bin/
```

Add `dashboard` to `.PHONY`. Destination is `bin/` (the note above said `bins/`).
`bin/` is gitignored and `Dockerfile` already does `COPY bin/ /app/bin/`, so the new
binary lands in the image with no Dockerfile change — but **the image must be rebuilt.**

### Step 3 — `local-compute/deploy-docker.sh`: one `cp` in Step 1 — DONE

Next to the existing `cp` lines that populate `$CONF_ROOT/vs` (`vs.toml`,
`attrfile.json`), before `docker compose up`:

```sh
cp "$CONF_TMPL/zpr-dashboard-config.toml" "$CONF_ROOT/vs/config.toml"   # zpr-dashboard reads ./config.toml
```

This belongs in the deploy script, not a manual step: `$CONF_ROOT` is `rm -rf`'d at the
top of every run.

### Step 4 — `commands/demo-zpr-dashboard` (new, `chmod +x`) — DONE

Modelled on `commands/demo-vs-admin`. `demo-vs-admin-gui` is untouched.

```bash
#!/usr/bin/env bash
# The zpr-dashboard TUI — a richer replacement for `demo-vs-admin gui`.
#
# Runs inside the vs container: the admin API listens on the vs ZPR address
# ([fd5a:5052::1]:8182), which is tun9 inside that container and unreachable from
# the host. cwd must be /conf because zpr-dashboard reads ./config.toml (planted
# there by deploy-docker.sh) and resolves its [files] paths relative to it. The
# API key goes in via -e like demo-vs-admin does: env beats the config file.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEYFILE="$MULTI_DIR/local-compute/client/client.key"
[ -f "$KEYFILE" ] || {
  echo "error: no vsapi key at $KEYFILE — run local-compute/deploy-docker.sh first" >&2
  exit 1
}
[ -t 0 ] && [ -t 1 ] || {
  echo "error: zpr-dashboard is a full-screen TUI; run it from a terminal" >&2
  exit 1
}

exec docker exec -it -w /conf \
  -e ZPR_API_KEY="$(cat "$KEYFILE")" \
  -e TERM="${TERM:-xterm-256color}" \
  vs /app/bin/zpr-dashboard
```

`-e TERM` because `docker exec` does not inherit the caller's `TERM` and lipgloss picks
its color depth from it. No `selftest` subcommand — there is no non-TTY mode to
exercise; see Verification step 4 for the one runnable check.

### Step 5 — docs — DONE

- `README.md`: a row in the "Handy commands" table right after `demo-vs-admin-gui` —
  `` | `demo-zpr-dashboard` | the `zpr-dashboard` TUI — richer than `demo-vs-admin gui` | ``
  — plus a sentence in the long-form vs-admin section pointing at it.
- `AGENTS.md`: add this file to the sub-plans list, marked DONE.

## Verification

1. **PASS** `make ZPR_ROOT=/home/mathias/src dashboard` → `bin/zpr-dashboard`,
   `file` reports ELF 64-bit LSB x86-64, Go, stripped. (`ZPR_ROOT` for this checkout is
   `/home/mathias/src`: the ZPR repos are siblings of `zpr-demo-gh`, not inside it.)
2. **PASS** `docker build -t zpr-multinode .` — `docker run --rm zpr-multinode ls -l
   /app/bin/` lists `zpr-dashboard` alongside the other six binaries.
3. **The one runnable check** — the config parses, without needing a TTY. `config.Load()`
   runs before bubbletea, so `Read config config.toml` / `Unknown key(s)` /
   `Parse dataplane.timeout` means the file is missing or malformed; any other failure
   means the config parsed and it died on the absent TTY, which is the expected outcome:
   ```sh
   T=$(mktemp -d); chmod 755 "$T"
   cp -r zpr-conf/include "$T/include"
   cp zpr-conf/confs/zpr-dashboard-config.toml "$T/config.toml"
   docker run --rm -v "$T:/conf" -w /conf -e ZPR_API_KEY=x zpr-multinode \
     /app/bin/zpr-dashboard </dev/null 2>&1
   ```
   **PASS** — fails only with `bubbletea: could not open TTY`. This also stands in for
   the live `docker exec -w /conf … vs` form: the mount mirrors what `deploy-docker.sh`
   assembles for `$CONF_ROOT/vs`, and `/conf/include/admin-tls-cert.pem` (what
   `ca = "include/admin-tls-cert.pem"` resolves to at cwd `/conf`) is present in it.
4. **PASS** `commands/demo-zpr-dashboard | cat` prints the "run from a terminal" message
   and exits 1.
5. **NOT RUN — needs a live environment.** `local-compute/deploy-docker.sh` requires
   `tofu -chdir=oci-compute output public_ips` for node0's address, and the OCI side is
   not currently applied. After `tofu apply` + `deploy-docker.sh`:
   - `docker exec vs ls /app/bin/zpr-dashboard /conf/config.toml` both succeed
   - `commands/demo-status` (all six `ph` up), then `commands/demo-zpr-dashboard` in a
     real terminal: the TUI paints, shows live visas/actors, `q` exits with the terminal
     restored
   - `commands/demo-vs-admin-gui` still works — nothing regressed
