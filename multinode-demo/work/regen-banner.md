# FEATURE: regen-banner

Currently the two web servers (`ociweb` and `premweb`) get a static
index file configured.  This is still fine. 

But now when the instances come up, I want to run a program on each
instance that updates that index file (overwrites it) with its output.

The program can be found at `../tools/regen-banner.sh`.  The usage for
it is: `./regen-banner.sh <INSTANCE_NAME> <INDEXFILE>`.

So on `ociweb` it needs to run as:
```sh
./regen-banner.sh OCIWEB /path/to/index.html
```

And on `premweb`:

```sh
./regen-banner.sh PREMWEB /path/to/index.html
```

This program should run continuously while the
hosts/instances/containers it is running on are up. 

## Implementation Plan

`tools/regen-banner.sh` is not modified by this plan. It loops forever, writing
the banner atomically (`.tmp` + `mv`) every 0.2s, so nginx never reads a partial
page.

Decisions:

- **Docker**: the docroot becomes container-local. The git-tracked
  `local-compute/web1-www/index.html` is deleted rather than churned 5×/sec
  through a read-write bind mount.
- **OCI**: installed via cloud-init `write_files` + a systemd unit, mirroring the
  existing `setup-tun9.sh` / `zpr-tun.service` pattern. No new deploy-script code.

The OCI static seed page (`oci-compute/web/index.html`, via `web_index`) stays —
it costs nothing and covers the boot window before `zpr-banner.service` starts.
Docker loses its seed page as a consequence of the container-local docroot; the
gap there is under a second.

### 1. `Dockerfile` — add `figlet` to the apt install list

Alongside `nginx`. Requires an image rebuild (`docker build -t zpr-multinode .`)
before the next `deploy-docker.sh` run.

### 2. `docker-compose.yml` — web1 volumes

- Remove `- ./local-compute/web1-www:/var/www/html:ro` and the comment above it
  about the single-file-bind-mount inode trap (no longer relevant).
- Add `- ./tools:/tools:ro`, so `regen-banner.sh` is reachable in-container and
  stays editable without an image rebuild — same rationale as the existing
  per-container entrypoint mounts.

### 3. Delete `local-compute/web1-www/index.html` (and the now-empty directory)

Its content is exactly what `regen-banner.sh PREMWEB` regenerates.

### 4. `local-compute/entrypoint-web1.sh` — start the banner before nginx

After the tun9 setup, before `exec nginx`:

```sh
# Live banner page: rewrite the docroot index every 0.2s (tools/regen-banner.sh).
# Backgrounded — nginx stays the exec target, and this dies with the container.
/tools/regen-banner.sh PREMWEB /var/www/html/index.html &
```

`set -e` is already on, but backgrounding means a failure here is silent — the
fetch-twice verification below is what catches it.

### 5. `oci-compute/compute.tf`

- `webserver` packages: `["tmux", "nginx", "figlet"]`.
- New templatefile var next to the existing `web_index`, same webserver-only
  conditional:

```hcl
banner = each.key == "webserver" ? file("${path.module}/../tools/regen-banner.sh") : ""
```

### 6. `oci-compute/cloud-init/host.yaml.tftpl`

- Widen the `write_files:` header guard to include `banner != ""`.
- New `%{ if banner != "" ~}` block adding two files, each with the same
  `${indent(6, ...)}` treatment as `web_index`:
  - `/usr/local/sbin/regen-banner.sh`, permissions `"0755"`, content = `banner`.
  - `/etc/systemd/system/zpr-banner.service`, permissions `"0644"` — long-running
    `Type=simple` (contrast `zpr-tun.service`'s `Type=oneshot`),
    `After=network-online.target nginx.service`,
    `ExecStart=/usr/local/sbin/regen-banner.sh OCIWEB /var/www/html/index.html`,
    `Restart=always`, `WantedBy=multi-user.target`.
- In `runcmd`, after the existing `systemctl daemon-reload` and guarded on
  `banner != ""`: `systemctl enable --now zpr-banner.service`.

Ordering matters: `figlet`/`nginx` are installed by the `runcmd` retry loops, so
the `enable --now` must stay after them — not in a `bootcmd`.

### 7. `README.md`

The live page is now generated, so editing `oci-compute/web/index.html` only
affects the boot-time placeholder. Replace the "Re-push the webserver index"
block with:

- Change the banner: edit `tools/regen-banner.sh`, then either
  `scp tools/regen-banner.sh ubuntu@<web_ip>:/tmp/ && ssh ... 'sudo install -m755 /tmp/regen-banner.sh /usr/local/sbin/ && sudo systemctl restart zpr-banner'`,
  or `tofu apply -replace='oci_core_instance.host["webserver"]'`.
- Docker side: `docker build -t zpr-multinode .` then re-run `deploy-docker.sh`
  (or just `docker compose restart web1` for a script-only edit, since `tools/`
  is mounted).
- Update the `curl http://<webserver_public_ip>/` expected output — it's the
  `OCIWEB` banner with a timestamp now, not `hello from OCI`.

## Verification

Static:

```bash
bash -n local-compute/entrypoint-web1.sh
tofu -chdir=oci-compute validate && tofu -chdir=oci-compute fmt -check
```

Docker — the real test is that the page *changes*:

```bash
docker build -t zpr-multinode .
./local-compute/deploy-docker.sh
docker exec web1 curl -s localhost | head -20     # PREMWEB banner + date
docker exec web1 sh -c 'curl -s localhost | tail -3; sleep 2; curl -s localhost | tail -3'
# ^ the two timestamps must differ; identical output = regen-banner not running
docker exec web1 pgrep -f regen-banner            # non-empty
```

OCI:

```bash
tofu -chdir=oci-compute apply -replace='oci_core_instance.host["webserver"]'
ssh -i ~/.ssh/zpr-demo ubuntu@<web_pub> \
  'systemctl status zpr-banner --no-pager; curl -s localhost | head -20'
```

End to end, from the alice host (existing `~/fetch` wrapper, `work/fetcher.md`):

```bash
./fetch http://ociweb.demo     # OCIWEB banner, green SUCCESS
./fetch http://premweb.demo    # PREMWEB banner, green SUCCESS
```

Mark item 11 DONE in `AGENTS.md` once implemented.
