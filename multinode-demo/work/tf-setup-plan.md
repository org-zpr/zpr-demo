# Multinode Demo — OCI Host Setup Plan (OpenTofu)

Goal of this pass: three Ubuntu 24.04 instances in OCI I can SSH into, that can
reach each other by IP and reach out to the internet, with the node's port 5000
open inbound. TUN interfaces configured (bonus). **No ZPR components installed
yet** — that's a later pass.

Base: copy `iot-demo/oci-compute/`, then strip everything ZPR/IoT-specific.

---

## 1. What we keep, drop, and change vs `iot-demo/oci-compute` — DONE

**Keep (near-verbatim):** `provider.tf`, the VCN/IGW/route-table/subnet in
`network.tf`, the instance resource shape/vnic pattern in `compute.tf`.

**Drop entirely:**
- `objectstorage.tf` — no binaries/certs to stage this pass. (Re-add later when
  ZPR artifacts need distributing.)
- `data "terraform_remote_state" "oci_iot"` + all IoT bridge plumbing.
- All `configs/*.tftpl` and the ZPR bits of the cloud-init.

**Change:**
- **OS = Ubuntu 24.04**, not Oracle Linux 9. Cascade of differences below.
- **Roles/names:** `webserver`, `node`, `vs` (was `device-a`, `device-b`, `zpr-core`).
- **Image via data source**, not a hardcoded OCID (Canonical publishes new
  Ubuntu images constantly; the OL9 OCID would be wrong anyway).

### Ubuntu-specific gotchas (the parts that will actually bite)
| Thing | OL9 (iot-demo) | Ubuntu 24.04 (here) |
|---|---|---|
| SSH user | `opc` | `ubuntu` |
| Package mgr | `dnf` + EPEL | `apt-get` |
| Host firewall | `firewalld` | `iptables` (OCI image ships rules that REJECT inbound except 22) |
| Firewall persist | `firewall-cmd --permanent` | `iptables -I INPUT 1 ...` + `netfilter-persistent save` (pkg `iptables-persistent`) |

The OCI Ubuntu image's default `INPUT` chain ends in a reject rule and only
allows established + SSH. SSH works out of the box; **anything else inbound
(port 80, 5000, inter-host IP) must be opened at the host too**, not just in the
security list. TUN itself needs no inbound ports until ZPR traffic flows, so for
the SSH+TUN goal this only matters for pre-opening 80/5000.

---

## 2. File layout — DONE

```
multinode-demo/oci-compute/
  provider.tf            # copy as-is
  variables.tf           # trimmed + Ubuntu image data source vars
  network.tf             # VCN/subnet kept; security list rewritten (section 4)
  compute.tf             # 3 instances, roles renamed, image from data source
  cloud-init/host.yaml.tftpl   # ONE template, parameterized by role
  web/index.html         # webserver landing page — editable, re-pushable (§5)
  outputs.tf             # public/private IPs + ssh commands (user=ubuntu)
  terraform.tfvars       # compartment_id + region
```

One cloud-init template for all three hosts — differences are small enough to
pass as variables. No object storage, so certs/binaries are simply absent.

---

## 3. `compute.tf` — three instances + image lookup — DONE

Replace the hardcoded `instance_image_id` with a data source:

```hcl
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}
# use: source_id = data.oci_core_images.ubuntu.images[0].id
```

Define the three hosts in a `for_each` map to avoid three copy-pasted blocks:

```hcl
locals {
  hosts = {
    webserver = { tun_addr = "fd5a:5052:8888::8", packages = ["tmux", "nginx"] }
    node      = { tun_addr = "fd5a:5052:90de::10", packages = ["tmux"] }
    vs        = { tun_addr = "fd5a:5052::1", packages = ["tmux", "valkey-server"] }
  }
}
# webserver index is a local repo file, editable + re-pushable (see §5).
```

resource "oci_core_instance" "host" {
  for_each            = local.hosts
  display_name        = "${var.name_prefix}-${each.key}"
  compartment_id      = var.compartment_id
  availability_domain = local.ad
  shape               = var.instance_shape
  shape_config { ocpus = var.instance_ocpus; memory_in_gbs = var.instance_memory_gb }
  source_details { source_type = "image"; source_id = data.oci_core_images.ubuntu.images[0].id }
  create_vnic_details { subnet_id = oci_core_subnet.public.id; assign_public_ip = true }
  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init/host.yaml.tftpl", {
      hostname = each.key
      tun_addr = each.value.tun_addr
      packages = each.value.packages
      # webserver only: content of the local index file, "" for the others.
      web_index = each.key == "webserver" ? file("${path.module}/web/index.html") : ""
    }))
  }
}
```

`packages` are the **non-ZPR** host software from PLAN.md §2 (nginx on webserver,
valkey on vs, tmux everywhere). Cheap to include now; drop the package list to
`["tmux"]` for all if you want pure bare hosts this pass.

---

## 4. `network.tf` — security list rules — DONE

VCN/IGW/route-table/subnet unchanged. Rewrite the security list ingress:

- **Egress:** allow all (unchanged — internet TCP/UDP out, PLAN §1).
- **SSH:** TCP 22 from `var.operator_cidr` (default `0.0.0.0/0`).
- **Inter-host:** allow all protocols from `var.subnet_cidr` (hosts talk by IP, PLAN §1).
- **Node substrate:** TCP **and** UDP 5000 from `0.0.0.0/0` (PLAN §1 — node
  inbound from outside).
- **Web:** TCP 80 from `0.0.0.0/0` (PLAN §2.1; harmless to pre-open).

```hcl
# node: TCP + UDP 5000 from anywhere
ingress_security_rules { source = "0.0.0.0/0"; protocol = "6"
  tcp_options { min = 5000; max = 5000 } description = "node 5000/tcp" }
ingress_security_rules { source = "0.0.0.0/0"; protocol = "17"
  udp_options { min = 5000; max = 5000 } description = "node 5000/udp" }
# webserver: http
ingress_security_rules { source = "0.0.0.0/0"; protocol = "6"
  tcp_options { min = 80; max = 80 } description = "http" }
# inter-host: everything within the subnet
ingress_security_rules { source = var.subnet_cidr; protocol = "all"
  description = "inter-host IP" }
```

The security list is shared across the subnet, so 80/5000 are technically open to
all three hosts at the OCI layer — but only the intended host listens on each, so
it's fine for a demo. Per-instance NSGs would tighten this; not worth it now.
<!-- ponytail: shared security list, switch to per-instance NSGs only if the demo needs true per-host isolation -->

---

## 5. `cloud-init/host.yaml.tftpl` — TUN + host packages — DONE

Ubuntu cloud-init. Installs packages, opens host firewall for 80/5000, brings up
a static TUN `tun9` with the role's ZPR address. TUN logic ported from
`iot-demo/setup/reset-tuns.sh` (single tun9 instead of tun8+tun9).

```yaml
#cloud-config
hostname: ${hostname}
package_update: true
packages:
%{ for p in packages ~}
  - ${p}
%{ endfor ~}
  - iptables-persistent

write_files:
  - path: /usr/local/sbin/setup-tun9.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail
      ip link show tun9 &>/dev/null && ip link delete tun9 || true
      ip tuntap add name tun9 mode tun multi_queue
      ip link set tun9 mtu 1400
      ip addr add ${tun_addr}/32 dev tun9      # /32 matches iot-demo's working config
      ip link set tun9 up
  - path: /etc/systemd/system/zpr-tun.service
    permissions: "0644"
    content: |
      [Unit]
      Description=ZPR static TUN (tun9)
      After=network-online.target
      Wants=network-online.target
      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/usr/local/sbin/setup-tun9.sh
      [Install]
      WantedBy=multi-user.target
%{ if web_index != "" ~}
  - path: /var/www/html/index.html
    permissions: "0644"
    content: |
      ${indent(6, web_index)}
%{ endif ~}

runcmd:
  # Open host firewall for the ports the security list already allows.
  # (OCI Ubuntu image rejects inbound except SSH; insert at top of INPUT.)
  - iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
  - iptables -I INPUT 1 -p tcp --dport 5000 -j ACCEPT
  - iptables -I INPUT 1 -p udp --dport 5000 -j ACCEPT
  - netfilter-persistent save
  - systemctl daemon-reload
  - systemctl enable --now zpr-tun.service
```

Notes:
- `${tun_addr}/32` is copied from the working `reset-tuns.sh`. It's an odd prefix
  for IPv6 but it's what the running demo uses — keep it until ZPR proves it needs
  `/64` or `/128`.
- Firewall ports are opened on every host for simplicity; only the relevant host
  actually listens. Same tradeoff as the shared security list.

**nginx index (PLAN §2.1):** kept as a local repo file
`oci-compute/web/index.html` (starter content: `hello from OCI`). It's read via
`file()` into the webserver's cloud-init `write_files` above, overwriting nginx's
default page on first boot. **Editable + re-pushable — with a caveat:** cloud-init
runs only at *first boot*, so editing the file and re-running `tofu apply` does
**not** repaint a live host. To push an update to a running webserver, either:
- `scp oci-compute/web/index.html ubuntu@<web_ip>:/tmp/ && ssh ... 'sudo mv /tmp/index.html /var/www/html/'` (fast), or
- `tofu apply -replace='oci_core_instance.host["webserver"]'` to rebuild that one host.
(When ZPR artifacts return via Object Storage next pass, the index can move there
and become re-pushable by plain re-apply.)

**valkey (PLAN §2.2):** Ubuntu's `valkey-server` package already listens on
`127.0.0.1:6379` by default — installing it (in the `vs` package list) is
expected to be enough. Verify with `ss -ltn | grep 6379` on the vs host after
boot; only add a `/etc/valkey/valkey.conf` drop-in if the default differs.

---

## 6. `variables.tf` / `outputs.tf` / `terraform.tfvars` — DONE

- **variables.tf:** keep `region`, `compartment_id`, `availability_domain`,
  `vcn_cidr`, `subnet_cidr`, `operator_cidr`, `instance_shape/ocpus/memory`,
  `ssh_public_key_path`, `name_prefix` (default `zpr-multinode`). **Drop**
  `instance_image_id`, `zpr_dir`, `*_binary_path`, `par_expiry`,
  `zpr_substrate_port` (inline 5000; only used in two rule blocks now).
- **outputs.tf:** iterate the `for_each` map — public IP, private IP, and an
  `ssh ubuntu@<public_ip>` command per host.
- **terraform.tfvars:** multinode uses its **own compartment** (different from
  iot-demo — do **not** reuse iot-demo's OCID):
  ```hcl
  region         = "us-ashburn-1"
  compartment_id = "ocid1.compartment.oc1..aaaaaaaayicy4pk637nctytdfvamd4fe4jbzhqnexhych7zpnqp5wsvjrhpq"
  ```

---

## 7. Apply & verify — CONFIG DONE (tofu init + validate pass; `tofu apply` not run — needs OCI creds/live infra)

```bash
cd multinode-demo/oci-compute
tofu init
tofu plan
tofu apply
# then, for each host:
ssh -i ~/.ssh/zpr-demo ubuntu@<public_ip>
ip addr show tun9          # expect the role's fd5a:... address, state UP
ping <other-host-private-ip>   # inter-host IP works
curl http://<webserver_public_ip>/     # "hello from OCI"
ss -ltn | grep 6379        # on vs host: valkey on 127.0.0.1:6379
```

Success = SSH into all three, `tun9` present with the right address on each,
hosts ping each other by private IP, the webserver returns "hello from OCI", and
valkey listens on the vs host.

---

## 8. Deferred to the next pass (explicitly NOT in this plan)

- ZPR binaries (`ph`, `vs`, tooling) + noise certs + policy `.bin2` → re-introduce
  Object Storage + PAR (from iot-demo `objectstorage.tf`) or `scp` from `bin/`.
- systemd units for node / adapters / visa service and the startup-order gates
  (PLAN §3–4).
- Tightening `operator_cidr` to a real /32.

(PLAN §2 non-ZPR software — tmux, nginx + index page, valkey — is now folded
into this pass, see §3/§5.)

---

## 9. Document it — update `README.md` (final step) — DONE

After the config applies cleanly, add a **"How to install"** section to
`multinode-demo/README.md` covering:
- prerequisites: `tofu` + `oci` CLI installed, `~/.oci/config` set up, the demo
  SSH key present;
- the apply flow: `cd <oci dir> && tofu init && tofu plan && tofu apply`;
- how to get the host IPs (`tofu output`) and SSH in (`ssh ubuntu@<ip>`);
- the verify checks from §7;
- how to re-push the webserver index (§5) and how to tear down (`tofu destroy`).

**Fix the README's directory name too:** README.md's Contents list calls the OCI
dir `remote-oci`; this demo uses **`oci-compute`** (matches iot-demo). Rename that
Contents entry when adding the install section.

## Open questions
1. SSH key path — reuse `~/.ssh/zpr-demo(.pub)` like iot-demo, or a new key?
   RESOLVED: reuse `~/.ssh/zpr-demo.pub` (default of `ssh_public_key_path`).
