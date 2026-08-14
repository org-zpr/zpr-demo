# FEATURE: fetcher script - **COMPLETED**

I need a script that wraps the `curl` command. This needs be able to run on my
local machine (so can live in `commands/`, and it must be present on the OCI
`alice` instance.

The purpose of this tool is to run a curl command then then add a banner at the
top indicating success or failure. Failure and success should ideally be
indicated by using a color (eg, GREEN success and RED failure).

Sample usage:

```sh

./fetch http://preweb.demo

[ OK SUCCESS ] successful fetch of http://preweb.demo at HH:MM:SS
... then follows the output from
... curl
... ...

```

Ideally the whole status line above has a green background or something. Example
of failure:

```sh
./fetch http://failing.blah

[ ERROR FAILED ] failed to load http://failing.blah at HH:MM:SS
... any curl error  output is here
... ...
```


## Implementation Plan

### Decisions

- Name is `fetch`, the same in both places: `commands/fetch` here, `~/fetch` on
  the `alice` OCI host, so `./fetch http://premweb.demo` reads identically in
  either. It skips the `demo-*` prefix the other commands use — that prefix is
  for tab-completion in `commands/`, and means nothing on alice.
- Failure is whatever `curl -f` calls a failure, so HTTP 4xx/5xx get the RED
  banner too, not just connect/DNS/timeout errors.
- `oci-compute/deploy-zpr.sh` scp's it to alice on every deploy.

### 1. `commands/fetch` (new, executable)

Standalone bash — deliberately does **not** source `commands/lib.sh`, so one
`scp` puts a working copy on alice. That is the one rule this script must keep.

- `fetch URL [curl-args…]`; args after the URL pass through to curl, so `-I`,
  `-v` and `-H …` keep working.
- `out=$(curl -fsS --max-time "${FETCH_TIMEOUT:-10}" "$@" "$url" 2>&1); rc=$?`
  — `set -uo pipefail` with **no `-e`**: a non-zero curl is the interesting
  case. stderr is folded into stdout so curl's error text lands under the
  banner. `FETCH_TIMEOUT` caps the wait, since a ZPR-denied fetch just hangs.
- Banner is one `printf` with ANSI SGR — green background (`\e[1;42;30m`) for
  `[ OK SUCCESS ] successful fetch of <url> at HH:MM:SS`, red (`\e[1;41;97m`)
  for `[ ERROR FAILED ] failed to load <url> at HH:MM:SS (curl exit N)`. Time
  from `date +%H:%M:%S`.
- Colors are dropped when stdout is not a TTY (`[ -t 1 ]`), so piping stays
  readable. No `tput`/terminfo dependency.
- Body prints after the banner; exit status is curl's, so `fetch … && …` works.

### 2. `fetch --selftest`

The banner is a branch, so it leaves one runnable check behind — same
convention as `commands/demo-attr selftest`, and offline like it: a
`file:///etc/hostname` fetch must print `OK SUCCESS`, an `http://127.0.0.1:1`
fetch must print `ERROR FAILED`. Two asserts, no server, no network.

### 3. `oci-compute/deploy-zpr.sh`

One `scp` in the alice block, after `start_ph … alice`, using the `$MULTI_DIR`
and `SSH_OPTS` already defined there. Lands in alice's login dir next to the
`/etc/hosts` entries the script already plants. Re-runnable: scp overwrites.

### 4. Docs

`README.md` gets one row in the commands table plus a mention in the self-check
note next to `demo-attr`. `commands/lib.sh` and its `NAMES` table are untouched:
`fetch` takes a URL, not a process name.

### Skipped

No retries, no `-w` timing line, no JSON pretty-printing, no shared library —
standalone is what makes it one `scp`.
