output "iot_device_host" {
  description = "MQTT endpoint for the mosquitto bridge: <device_host>:8883 over TLS."
  value       = var.iot_device_host
}

output "device_a_username" {
  description = "MQTT username for the bridge (the instance external key)."
  value       = "device-a"
}

output "device_a_password" {
  description = "MQTT password for the bridge. Retrieve with: tofu output -raw device_a_password"
  value       = random_password.device_a.result
  sensitive   = true
}

output "device_a_secret_ocid" {
  description = "OCID of the vault secret backing device_a's auth."
  value       = oci_vault_secret.device_a.id
}

output "device_a_instance_ocid" {
  description = "Digital twin instance OCID for device_a."
  value       = module.device_a_instance.digital_twin_instance_tf_id
}

output "digital_twin_model_ocid" {
  description = "Digital twin model OCID."
  value       = module.device_model.digital_twin_model_tf_id
}
