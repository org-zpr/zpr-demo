# Multinode Demo — Drop the "vs" OCI Host (OpenTofu)

PLAN.md now calls for **two** OCI hosts (`webserver`, `node`), not three. The
`vs` host — valkey + visa service — moves to the local docker env (PLAN §5/§6)
and is no longer stood up in OCI. This plan removes it from `oci-compute/`.

Good news: `vs` is confined to **one file**. The instances, VNICs, and outputs
are all driven off the `for_each` over `local.hosts` in `compute.tf`, so
deleting one map entry cascades everywhere automatically. No changes needed to
`network.tf`, `outputs.tf`, `variables.tf`, `provider.tf`, or the cloud-init
template.

---

## 1. `compute.tf` — remove the `vs` entry ✅ DONE

Delete the `vs` line from `local.hosts`:

```hcl
  hosts = {
    webserver = { tun_addr = "fd5a:5052:8888::8", packages = ["tmux", "nginx"] }
    node      = { tun_addr = "fd5a:5052:90de::10", packages = ["tmux"] }
-   vs        = { tun_addr = "fd5a:5052::1", packages = ["tmux", "valkey-server"] }
  }
```

And drop the `#   vs        : valkey-server` line from the header comment block
at the top of the file. Change "three Ubuntu 24.04 instances" → "two" in that
same comment.

That's the whole config change. `for_each` now iterates two hosts; the
`oci_core_instance.host["vs"]` resource and its outputs disappear on their own.

---

## 2. `README.md` — fix the three stale references ✅ DONE

- Line ~12: "three Ubuntu 24.04 instances (`webserver`, `node`, `vs`)" → "two …
  (`webserver`, `node`)".
- Line ~14: drop "and valkey on the vs host".
- Line ~41: delete the `ss -ltn | grep 6379 … on vs host` verify line.

---

## 3. Apply ✅ DONE (validate + plan only; state empty, nothing live to destroy)

State currently has no instances (`terraform.tfstate` is empty), so this is a
no-op destroy — just re-validate:

```bash
cd multinode-demo/oci-compute
tofu validate
tofu plan            # expect: two instances to create, zero vs references
```

If a `vs` instance *is* live in some state when you apply, `tofu apply` will
**destroy it** (it's no longer in the config) — that's the intended outcome.

<!-- ponytail: valkey-server package stays referenced in tf-setup-plan.md §3/§5 as historical record; not worth rewriting a DONE plan. -->

---

## Out of scope

- The local docker env that will now host valkey + the visa service (PLAN §5/§6)
  — separate pass.
- `tf-setup-plan.md` is left as-is (it's a completed record of the old
  three-host build); this plan supersedes its host count.
