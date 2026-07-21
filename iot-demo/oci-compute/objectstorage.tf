############################
# Object Storage — staging for STATIC artifacts each instance pulls at boot:
# the ph/vs binaries, the compiled policy, and the cert/key files. Delivered via
# a pre-authenticated request (PAR) so instances need no OCI creds (instance
# principals aren't an option — they'd need a tenancy-level dynamic group + policy
# this account can't create).
#
# NOTE: the .toml *configs* are NOT here — they need per-instance node_addr values
# (zpr-core's private IP / 127.0.0.1) that Terraform only knows after create, so
# they're rendered into each instance's cloud-init via templatefile() instead.
# Split: big/static/same-everywhere -> bucket; small/needs-a-computed-value -> cloud-init.
#
# Object layout in the bucket:
#   bin/       ph, vs                          (shared big binaries)
#   shared/    auth-ca.crt, node-noise-pub.pem (small, needed by multiple roles)
#   core/      policy + node/vs/egress keys    (zpr-core only)
#   device-a/  ingress keys                     (device-a only)
#   device-b/  ingress2 keys                    (device-b only)
#
# The CA *private* key (authority/auth-ca.key) is deliberately NOT uploaded — it's
# the root of trust and never leaves the operator laptop.
############################

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "artifacts" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "${var.name_prefix}-artifacts"
  access_type    = "NoPublicAccess"
}

locals {
  setup = "${path.module}/../setup"

  # object_name (key in the bucket) => local source file
  artifacts = {
    # --- shared binaries ---
    "bin/ph"       = var.ph_binary_path
    "bin/vs"       = var.vs_binary_path
    "bin/vsapikey" = var.vsapikey_binary_path

    # --- shared small files (multiple roles reference these) ---
    "shared/auth-ca.crt"        = "${local.setup}/authority/auth-ca.crt"
    "shared/node-noise-pub.pem" = "${local.setup}/node/node-noise-pub.pem"

    # --- zpr-core: policy + node / vs / egress cert+key material ---
    "core/iot-demo.bin2"                 = "${local.setup}/iot-demo.bin2"
    "core/node/node-noise.crt"           = "${local.setup}/node/node-noise.crt"
    "core/node/node-noise.key"           = "${local.setup}/node/node-noise.key"
    "core/node/node-private-key.pem"     = "${local.setup}/node/node-private-key.pem"
    "core/vs/vs-noise.crt"               = "${local.setup}/vs/vs-noise.crt"
    "core/vs/vs-noise.key"               = "${local.setup}/vs/vs-noise.key"
    "core/vs/vs-private-key.pem"         = "${local.setup}/vs/vs-private-key.pem"
    "core/vs/admin-tls-cert.pem"         = "${local.setup}/vs/admin-tls-cert.pem"
    "core/vs/admin-tls-key.pem"          = "${local.setup}/vs/admin-tls-key.pem"
    "core/egress/egress-noise.crt"       = "${local.setup}/egress/egress-noise.crt"
    "core/egress/egress-noise.key"       = "${local.setup}/egress/egress-noise.key"
    "core/egress/egress-private-key.pem" = "${local.setup}/egress/egress-private-key.pem"

    # --- device-a: ingress cert+key material + device script ---
    "device-a/ingress-noise.crt"       = "${local.setup}/ingress/ingress-noise.crt"
    "device-a/ingress-noise.key"       = "${local.setup}/ingress/ingress-noise.key"
    "device-a/ingress-private-key.pem" = "${local.setup}/ingress/ingress-private-key.pem"
    "device-a/device_a.py"             = "${path.module}/../devices/device_a.py"

    # --- device-b: ingress2 cert+key material + device script ---
    "device-b/ingress2-noise.crt"       = "${local.setup}/ingress2/ingress2-noise.crt"
    "device-b/ingress2-noise.key"       = "${local.setup}/ingress2/ingress2-noise.key"
    "device-b/ingress2-private-key.pem" = "${local.setup}/ingress2/ingress2-private-key.pem"
    "device-b/device_b.py"              = "${path.module}/../devices/device_b.py"
  }
}

resource "oci_objectstorage_object" "artifact" {
  for_each = local.artifacts

  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.artifacts.name
  object    = each.key
  source    = each.value
}

# --- PAR: one read-only, time-limited URL for the whole bucket ---
# AnyObjectRead means any instance can read any object (including another role's
# keys). For a short-lived demo of your own instances that's acceptable; per-object
# PARs would isolate roles but mean ~20 URLs to thread into cloud-init.
resource "oci_objectstorage_preauthrequest" "artifacts" {
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  bucket       = oci_objectstorage_bucket.artifacts.name
  name         = "${var.name_prefix}-artifacts-par"
  access_type  = "AnyObjectRead"
  time_expires = var.par_expiry
}

# Full URL prefix cloud-init curls objects from: "<region-uri><access_uri>".
# access_uri is a path like /p/<token>/n/<ns>/b/<bucket>/o/ — append the object name.
locals {
  par_base_url = "https://objectstorage.${var.region}.oraclecloud.com${oci_objectstorage_preauthrequest.artifacts.access_uri}"
}
