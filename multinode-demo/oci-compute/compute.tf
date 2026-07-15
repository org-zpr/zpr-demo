############################
# Compute — three Ubuntu 24.04 instances in the one public subnet.
#   webserver : nginx + landing page (web/index.html)
#   node      : ZPR substrate host (5000/tcp+udp open) — bare this pass
#   vs        : valkey-server
# One cloud-init template for all three, parameterized by role. No ZPR
# binaries yet — that's a later pass.
############################

locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  hosts = {
    webserver = { tun_addr = "fd5a:5052:8888::8", packages = ["tmux", "nginx"] }
    node      = { tun_addr = "fd5a:5052:90de::10", packages = ["tmux"] }
    vs        = { tun_addr = "fd5a:5052::1", packages = ["tmux", "valkey-server"] }
  }
}

# Ubuntu image via data source — Canonical publishes new images constantly, so a
# hardcoded OCID would be stale. Newest 24.04 for the shape wins.
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "host" {
  for_each            = local.hosts
  compartment_id      = var.compartment_id
  availability_domain = local.ad
  display_name        = "${var.name_prefix}-${each.key}"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init/host.yaml.tftpl", {
      hostname = each.key
      tun_addr = each.value.tun_addr
      packages = each.value.packages
      vcn_cidr = var.vcn_cidr
      # webserver only: content of the local index file, "" for the others.
      web_index = each.key == "webserver" ? file("${path.module}/web/index.html") : ""
    }))
  }
}
