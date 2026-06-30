############################
# IoT data path on the EXISTING domain (ZPR-Demo-Domain).
# model -> adapter -> cert-auth instance. device_b is blocked by ZPR before it
# reaches the egress mosquitto, so only device_a needs an instance.
############################

module "device_model" {
  source = "./modules/iot/digitaltwinmodel"

  iot_domain_id = var.iot_domain_id
  display_name  = "${var.name_prefix}-device-model"
  description   = "ZPR demo device telemetry model"
  spec          = file("${path.module}/data/device-a-model.json")
  defined_tags  = {} # don't apply the module's Oracle-Tags defaults (not authorized)
}

module "device_a_adapter" {
  source = "./modules/iot/digitaltwinadapter"

  iot_domain_id         = var.iot_domain_id
  display_name          = "${var.name_prefix}-device-a-adapter"
  description           = "Maps device_a MQTT payload to the device model"
  digital_twin_model_id = module.device_model.digital_twin_model_tf_id

  inbound_envelope = jsondecode(file("${path.module}/data/device-a-adapter-envelope.json"))
  inbound_routes   = jsondecode(file("${path.module}/data/device-a-adapter-routes.json"))
  defined_tags     = {}
}

module "device_a_instance" {
  source = "./modules/iot/digitaltwininstance"

  iot_domain_id           = var.iot_domain_id
  display_name            = "${var.name_prefix}-device-a"
  description             = "Digital twin instance for ZPR demo device_a (basic/secret auth)"
  digital_twin_adapter_id = module.device_a_adapter.digital_twin_adapter_tf_id
  auth_id                 = oci_vault_secret.device_a.id
  external_key            = "device-a" # MQTT username the bridge presents
  defined_tags            = {}
}
