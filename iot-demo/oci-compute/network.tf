############################
# Network — one VCN, one public subnet, all three instances share it.
# ZPR does the access control; this layer just must not silently block the
# substrate. Security-list rules are LAYER 1 of 2 — the host firewalld on each
# instance (opened in cloud-init) is layer 2. Both default-deny, both fail silently.
############################

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

locals {
  ad = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.ads.availability_domains[0].name
}

resource "oci_core_vcn" "demo" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.name_prefix}-vcn"
  dns_label      = "zpriot"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.demo.id
  display_name   = "${var.name_prefix}-igw"
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.demo.id
  display_name   = "${var.name_prefix}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# --- Security list: the OCI-layer firewall (ats's "let everything through" point) ---
resource "oci_core_security_list" "demo" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.demo.id
  display_name   = "${var.name_prefix}-sl"

  # Egress: allow all (bridge to OCI IoT :8883, package installs, object storage).
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Ingress: ZPR substrate (UDP 5000) between instances in the subnet.
  ingress_security_rules {
    source   = var.subnet_cidr
    protocol = "17" # UDP
    udp_options {
      min = var.zpr_substrate_port
      max = var.zpr_substrate_port
    }
    description = "ZPR substrate (adapter -> node), UDP"
  }

  # Ingress: SSH from the operator.
  ingress_security_rules {
    source   = var.operator_cidr
    protocol = "6" # TCP
    tcp_options {
      min = 22
      max = 22
    }
    description = "SSH for provisioning + post-init hand-off"
  }

  # TODO: consider whether ICMP (for path-MTU / ping debugging) is worth allowing.
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.demo.id
  cidr_block        = var.subnet_cidr
  display_name      = "${var.name_prefix}-subnet"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.demo.id]
  dns_label         = "zpriot"
}
