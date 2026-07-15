############################
# Network — one VCN, one public subnet, all three instances share it.
# Security-list rules are LAYER 1 of 2 — the host iptables on each Ubuntu
# instance (opened in cloud-init) is layer 2. Both default-deny inbound.
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
  dns_label      = "zprmulti"
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

# --- Security list: the OCI-layer firewall ---
# Shared across the subnet, so 80/5000 are technically open to all three hosts
# at the OCI layer — but only the intended host listens on each, fine for a demo.
# ponytail: shared security list, switch to per-instance NSGs only if the demo needs true per-host isolation
resource "oci_core_security_list" "demo" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.demo.id
  display_name   = "${var.name_prefix}-sl"

  # Egress: allow all (internet TCP/UDP out — package installs, etc.).
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH from the operator.
  ingress_security_rules {
    source   = var.operator_cidr
    protocol = "6" # TCP
    tcp_options {
      min = 22
      max = 22
    }
    description = "SSH"
  }

  # Inter-host: everything within the subnet (hosts talk by private IP).
  ingress_security_rules {
    source      = var.subnet_cidr
    protocol    = "all"
    description = "inter-host IP"
  }

  # node substrate: TCP 5000 from anywhere.
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      min = 5000
      max = 5000
    }
    description = "node 5000/tcp"
  }

  # node substrate: UDP 5000 from anywhere.
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "17" # UDP
    udp_options {
      min = 5000
      max = 5000
    }
    description = "node 5000/udp"
  }

  # webserver: HTTP — intra-VCN only. External access is ZPR-managed, so 80 is
  # NOT open to the internet; only in-OCI hosts (incl. ZPR components) reach it.
  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = "6" # TCP
    tcp_options {
      min = 80
      max = 80
    }
    description = "http (intra-VCN; external via ZPR)"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.demo.id
  cidr_block        = var.subnet_cidr
  display_name      = "${var.name_prefix}-subnet"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.demo.id]
  dns_label         = "zprmulti"
}
