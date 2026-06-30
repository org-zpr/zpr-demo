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
