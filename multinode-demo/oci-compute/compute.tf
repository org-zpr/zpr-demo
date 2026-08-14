############################
# Compute — three Ubuntu 24.04 instances in the one public subnet.
#   webserver : nginx + landing page (web/index.html)
#   node      : ZPR substrate host (5000/tcp+udp open)
#   alice     : "alice" user workstation — runs an adapter, operator curls from it
# One cloud-init template for all, parameterized by role.
############################

locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  hosts = {
    webserver = { tun_addr = "fd5a:5052:8888::8", packages = ["tmux", "nginx", "figlet"] }
    node      = { tun_addr = "fd5a:5052:90de::10", packages = ["tmux"] }
    # alice's ZPR address is dynamic (assigned by the visa service), so its
    # adapter config sets no tun_if and `ph` creates its own TUN — hence no
    # static tun9 here, and the adapter runs under sudo.
    alice = { tun_addr = "", packages = ["tmux", "curl"] }
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
      # webserver only: content of the local index file, "" for the others. Only
      # the boot-time placeholder now — zpr-banner.service overwrites it.
      web_index = each.key == "webserver" ? file("${path.module}/web/index.html") : ""
      # webserver only: the live-banner generator, installed + run by systemd.
      banner = each.key == "webserver" ? file("${path.module}/../tools/regen-banner.sh") : ""
    }))
  }
}
