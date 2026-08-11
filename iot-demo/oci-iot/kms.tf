############################
# Vault + AES key — encrypts the device's auth secret.
# Basic (password) auth needs no CA/RSA key; just a vault to hold the secret.
############################

resource "oci_kms_vault" "iot" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vault"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "secret_encryption" {
  compartment_id      = var.compartment_id
  display_name        = "${var.name_prefix}-secret-key"
  management_endpoint = oci_kms_vault.iot.management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32 # bytes → AES-256
  }
}
