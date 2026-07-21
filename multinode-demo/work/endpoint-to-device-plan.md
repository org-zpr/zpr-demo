# **DONE** Plan: `endpoint` → `device` in the multinode demo

The ZPL class `endpoint` was renamed to `device` (see
`../../../zpr-compiler/endpoint-to-device-plan.md`). This is a **breaking
wire-format change** — the fabric and the compiled policy must move in
lockstep. ZPR binaries in `bin/` are already rebuilt (`zplc` reports
`0.13.0`; it now *rejects* `endpoint.zpr.adapter.cn` and accepts
`device.zpr.adapter.cn` — verified).

## What actually needs editing: one file, 4 lines

Only the attribute *domain* string changed, and this demo touches it in
exactly one source file:

- **`zpr-conf/admin/multinode-demo.zplc.template`** — replace all four
  `endpoint.zpr.adapter.cn` → `device.zpr.adapter.cn` (lines 4, 11, 43, 48:
  the two `[nodes.*]` providers and the two `[services.*]` providers).

Nothing else references `endpoint` (grepped the whole demo tree). In
particular:

- **`multinode-demo.zpl`** needs **no change** — it only uses `define … as a
  service` and the built-in `user`; it never names the `endpoint`/`device`
  class.
- The adapter conf templates (`zpr-conf/confs/adapter-*.toml.template`) and
  all deploy scripts contain no `endpoint` references.

### Also new in 0.13.0: every ZPL statement must end with `.`

Checked `multinode-demo.zpl` — all four statements (`define OciWeb…`,
`define PremWeb…`, `allow user to access OciWeb…`, `allow user to access
PremWeb…`) already end with a period, so **no change needed**. Keep this in
mind if the `.zpl` is edited later.

## Regenerated artifacts — no manual edit

These are build outputs, regenerated on every deploy from the template above;
just delete the stale copies (or let the deploy overwrite them):

- `zpr-conf/admin/multinode-demo.zplc` (rendered by `deploy-docker.sh` from
  the `.template`)
- `zpr-conf/admin/multinode-demo.bin2` / `local-compute/conf/vs/multinode-demo.bin2`
  (compiled by `zplc` in `deploy-docker.sh:69–70`)

Neither is git-tracked, so no commit churn.

Redeploy/rebuild of running instances is out of scope here — done later.

## Verify

```sh
# 1. no endpoint refs left in sources
grep -rni endpoint . | grep -v endpoint-to-device-plan.md   # → empty

# 2. policy compiles clean under the new zplc (from a rendered .zplc)
cd zpr-conf/admin && ../../bin/zplc --config multinode-demo.zplc multinode-demo.zpl
```
