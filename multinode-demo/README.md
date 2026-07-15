# Multinode Demo

## Contents

- `bin` - Binaries to run for the demo
- `local-compute` - Setup code for the local ("on prem") containers.
- `oci-compute` - OpenTofu setup for the remote (OCI cloud) instances.
- `zpr-conf` - All the ZPR config files, certificates, policy, etc.

## How to install (OCI hosts)

Brings up three Ubuntu 24.04 instances (`webserver`, `node`, `vs`) in OCI —
SSH-reachable, able to reach each other by private IP, with a `tun9` interface,
nginx on the webserver, and valkey on the vs host. No ZPR components yet.

**Prerequisites:** `tofu` + `oci` CLIs installed, `~/.oci/config` set up (profile
`DEFAULT`), and the demo SSH key present at `~/.ssh/zpr-demo(.pub)`.

**Apply:**

```bash
cd oci-compute
tofu init
tofu plan
tofu apply
```

**Get IPs and SSH in:**

```bash
tofu output              # public_ips, private_ips, ssh_commands
ssh -i ~/.ssh/zpr-demo ubuntu@<public_ip>
```

**Verify (per host):**

```bash
ip addr show tun9                       # role's fd5a:... address, state UP
ping <other-host-private-ip>            # inter-host IP works
curl http://<webserver_public_ip>/      # "hello from OCI"
ss -ltn | grep 6379                     # on vs host: valkey on 127.0.0.1:6379
```

**Re-push the webserver index:** cloud-init only runs at first boot, so editing
`oci-compute/web/index.html` and re-applying does NOT repaint a live host. Either:

```bash
scp oci-compute/web/index.html ubuntu@<web_ip>:/tmp/ && \
  ssh ubuntu@<web_ip> 'sudo mv /tmp/index.html /var/www/html/'
# or rebuild just that host:
tofu apply -replace='oci_core_instance.host["webserver"]'
```

**Tear down:** `tofu destroy`.

