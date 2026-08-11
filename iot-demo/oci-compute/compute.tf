############################
# Compute — three instances, all in the one public subnet.
#   device-a : device_a.py + ingress adapter
#   device-b : device_b.py + ingress2 adapter (blocked by ZPR policy)
#   zpr-core : valkey, node, VS adapter, visa service, egress adapter, mosquitto
#              + OCI bridge — all NATIVE, no Docker.
# cloud-init per role installs deps, opens firewalld (layer 2), drops binaries/
# certs pulled from Object Storage, and starts each process.
############################

locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  # node_addr per role: co-located adapters use localhost; device adapters dial
  # zpr-core's private IP across the subnet (known only after zpr-core is created).
  node_addr_core   = "127.0.0.1:${var.zpr_substrate_port}"
  node_addr_device = "${oci_core_instance.zpr_core.private_ip}:${var.zpr_substrate_port}"

  # zpr-core cloud-init (renders the four configs inline).
  zpr_core_user_data = base64encode(templatefile("${path.module}/cloud-init/zpr-core.yaml.tftpl", {
    par_base_url        = local.par_base_url
    zpr_dir             = var.zpr_dir
    zpr_substrate_port  = var.zpr_substrate_port
    oci_device_host       = data.terraform_remote_state.oci_iot.outputs.iot_device_host
    oci_device_username   = data.terraform_remote_state.oci_iot.outputs.device_a_username
    oci_device_password   = data.terraform_remote_state.oci_iot.outputs.device_a_password
    oci_device_b_username = data.terraform_remote_state.oci_iot.outputs.device_b_username
    oci_device_b_password = data.terraform_remote_state.oci_iot.outputs.device_b_password
    node_conf           = templatefile("${path.module}/configs/node-conf.toml.tftpl", { zpr_dir = var.zpr_dir })
    vs_adapter_conf     = templatefile("${path.module}/configs/adapter-vs-conf.toml.tftpl", { zpr_dir = var.zpr_dir, node_addr = local.node_addr_core })
    vs_conf             = templatefile("${path.module}/configs/vs-conf.toml.tftpl", { zpr_dir = var.zpr_dir })
    egress_conf         = templatefile("${path.module}/configs/egress-adapter-conf.toml.tftpl", { zpr_dir = var.zpr_dir, node_addr = local.node_addr_core })
  }))

  device_a_user_data = base64encode(templatefile("${path.module}/cloud-init/device.yaml.tftpl", {
    par_base_url   = local.par_base_url
    zpr_dir        = var.zpr_dir
    role_prefix    = "device-a"
    adapter_name   = "device-a"
    device_script  = "device_a.py"
    device_restart = "on-failure" # allowed device: self-heal if the connection drops
    adapter_config = templatefile("${path.module}/configs/device-a-adapter-conf.toml.tftpl", {
      zpr_dir = var.zpr_dir, node_addr = local.node_addr_device
    })
  }))

  device_b_user_data = base64encode(templatefile("${path.module}/cloud-init/device.yaml.tftpl", {
    par_base_url   = local.par_base_url
    zpr_dir        = var.zpr_dir
    role_prefix    = "device-b"
    adapter_name   = "device-b"
    device_script  = "device_b.py"
    device_restart = "no" # blocked device: fail once and stay down (no restart loop)
    adapter_config = templatefile("${path.module}/configs/device-b-adapter-conf.toml.tftpl", {
      zpr_dir = var.zpr_dir, node_addr = local.node_addr_device
    })
  }))
}

# Bridge credentials come from the oci-iot stack's outputs (avoids duplicating the
# vault password here). That stack must be applied first — it's a demo prerequisite.
data "terraform_remote_state" "oci_iot" {
  backend = "local"
  config = {
    path = "${path.module}/../oci-iot/terraform.tfstate"
  }
}

# --- device-a ---
resource "oci_core_instance" "device_a" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad
  display_name        = "${var.name_prefix}-device-a"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = var.instance_image_id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data           = local.device_a_user_data
  }
}

# --- device-b ---
resource "oci_core_instance" "device_b" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad
  display_name        = "${var.name_prefix}-device-b"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = var.instance_image_id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data           = local.device_b_user_data
  }
}

# --- zpr-core ---
resource "oci_core_instance" "zpr_core" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad
  display_name        = "${var.name_prefix}-zpr-core"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = var.instance_image_id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data           = local.zpr_core_user_data
  }
}
