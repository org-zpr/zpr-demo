# FEATURE: populate hosts files

The demo will involve attempting to use `curl` to access web services on
the `premweb.demo` actor and the `ociweb.demo` actor.

Ensure that there are host file entries for the two actors on the
following machines:

- `admin.demo`

The correct hosts file entries are:

```
fd5a:5052:8888::9 premweb.demo
fd5a:5052:8888::8 ociweb.demo
```

## Where this goes

- `oci-compute/deploy-zpr.sh` — the post-`tofu apply` configurator for the OCI
  hosts. It already resolves `$ADMIN_PUB`, already has `ssh_h()`
  (`deploy-zpr.sh:22`), already `sudo`s on that host, and is re-runnable. The
  write goes right after the admin block (`deploy-zpr.sh:127-128`), before the
  closing `echo` banner.
- Not cloud-init (`oci-compute/cloud-init/host.yaml.tftpl`): user_data only
  takes effect on a freshly created instance, so the running admin host would
  stay unfixed until a destroy/apply.
- No helper, no loop — `admin` is the only host that curls. Generalize if that
  changes.
- Supersedes the "the operator writes `/etc/hosts` by hand" decision at
  `work/scripts-plan.md:17`.

## Implementation Steps

### Step 1 — write the entries — DONE

`oci-compute/deploy-zpr.sh`, immediately after the `start_ph … admin … "sudo "`
call (line 128). Delete-then-append so a re-run replaces rather than stacks:

```bash
# --- /etc/hosts for the demo web actors ---
# Addresses are fixed by policy (zpr-conf/admin/multinode-demo.zplc.template),
# so there is nothing to derive — just plant them. Delete-then-append keeps a
# re-run from duplicating the lines.
ssh_h "$ADMIN_PUB" "sudo sed -i '/ premweb\.demo\$/d;/ ociweb\.demo\$/d' /etc/hosts; \
  printf 'fd5a:5052:8888::9 premweb.demo\nfd5a:5052:8888::8 ociweb.demo\n' \
    | sudo tee -a /etc/hosts >/dev/null"
echo "[admin] /etc/hosts: premweb.demo, ociweb.demo"
```

Two escaping traps: `\.` and `\$` have to survive the outer double-quoted ssh
string, and the `printf` format carries two real `\n` — no leading space on the
second entry.

### Step 2 — cross-reference — DONE

`work/scripts-plan.md:16-17`: append to the "No `demo-hosts.txt`" bullet that
`deploy-zpr.sh` now plants the entries — see this file.

### Step 3 — README — DONE

One line in the OCI install section of `README.md`: `deploy-zpr.sh` also writes
`premweb.demo` / `ociweb.demo` into the admin host's `/etc/hosts`, so
`curl http://ociweb.demo/` works from there.

### Step 4 — mark DONE — DONE

Add `9. work/hosts-files.md - DONE` to the sub-plan list in `AGENTS.md` once
verified.

## Verification — DONE (1–3 pass, 4 blocked)

Run 2026-08-11 against the live OCI hosts (admin `129.213.20.45`).

1. **PASS** — `oci-compute/deploy-zpr.sh` completed and printed
   `[admin] /etc/hosts: premweb.demo, ociweb.demo`.
2. **PASS** — `getent hosts ociweb.demo premweb.demo` on the admin host returns
   `fd5a:5052:8888::8 ociweb.demo` / `fd5a:5052:8888::9 premweb.demo`.
   (`/etc/hosts` lines 12–13; the file had no `demo` entries beforehand.)
3. **PASS** — re-ran `deploy-zpr.sh`; `grep -c "web\.demo" /etc/hosts` → `2`,
   not `4`.
4. **BLOCKED** — `curl -sS -m 15 http://ociweb.demo/` → `curl: (7) Failed to
   connect`. Not a hosts-file problem: name resolution is fine, the ZPR path
   isn't. `~/zpr/adapter.log` on admin shows the dock link cycling
   (`Shutting down dock link` → `Attempting to restart` → `verified name
   CN=node0.demo`, repeat) and `tun0` is `DOWN`, i.e. no visa issued. That is
   the pre-existing node0↔node1 link gap called out in the `TODO` at
   `deploy-zpr.sh:109-114`. Re-check this step once that link works.
