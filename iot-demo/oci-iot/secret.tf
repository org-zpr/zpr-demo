############################
# device_a auth secret — the password the mosquitto bridge presents to OCI IoT.
# Auto-generated, stored in the vault, and surfaced as a sensitive output.
############################

resource "random_password" "device_a" {
  length           = 24
  special          = true
  override_special = "_-." # keep it MQTT/shell-friendly
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
}

resource "oci_vault_secret" "device_a" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.iot.id
  key_id         = oci_kms_key.secret_encryption.id
  secret_name    = "${var.name_prefix}-device-a"
  description    = "Auth password for ZPR demo device_a digital twin instance"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.device_a.result)
  }
}

############################
# device_b auth secret — mirrors device_a. device_b now flows through ZPR to its
# own digital twin instance (previously blocked by policy).
############################

resource "random_password" "device_b" {
  length           = 24
  special          = true
  override_special = "_-." # keep it MQTT/shell-friendly
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
}

resource "oci_vault_secret" "device_b" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.iot.id
  key_id         = oci_kms_key.secret_encryption.id
  secret_name    = "${var.name_prefix}-device-b"
  description    = "Auth password for ZPR demo device_b digital twin instance"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.device_b.result)
  }
}
