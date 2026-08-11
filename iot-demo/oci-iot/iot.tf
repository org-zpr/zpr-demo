############################
# IoT data path on the EXISTING domain (ZPR-Demo-Domain).
# model -> adapter -> secret-auth instance. Both devices flow through ZPR to their
# own instances. Each device has its OWN model + adapter: the payloads differ
# (device_a temperature/humidity vs device_b co2/pressure), and OCI binds
# instance<->adapter 1:1 anyway (a shared adapter leaves the second instance's
# MQTT connection unroutable — CONNECT dropped).
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

# device_b reports a DIFFERENT payload than device_a (co2_ppm / pressure_hpa vs
# temperature_c / humidity_pct), so it needs its own model as well as its own adapter.
module "device_b_model" {
  source = "./modules/iot/digitaltwinmodel"

  iot_domain_id = var.iot_domain_id
  display_name  = "${var.name_prefix}-device-b-model"
  description   = "ZPR demo device_b CO2/pressure telemetry model"
  spec          = file("${path.module}/data/device-b-model.json")
  defined_tags  = {}
}

module "device_b_adapter" {
  source = "./modules/iot/digitaltwinadapter"

  iot_domain_id         = var.iot_domain_id
  display_name          = "${var.name_prefix}-device-b-adapter"
  description           = "Maps device_b CO2/pressure MQTT payload to the device_b model"
  digital_twin_model_id = module.device_b_model.digital_twin_model_tf_id

  # OCI binds each instance to its OWN adapter — a shared adapter makes the second
  # instance's MQTT connection unroutable (OCI drops the CONNECT). device_b's payload
  # differs from device_a's, so its envelope/routes map co2_ppm + pressure_hpa.
  inbound_envelope = jsondecode(file("${path.module}/data/device-b-adapter-envelope.json"))
  inbound_routes   = jsondecode(file("${path.module}/data/device-b-adapter-routes.json"))
  defined_tags     = {}
}

module "device_b_instance" {
  source = "./modules/iot/digitaltwininstance"

  iot_domain_id           = var.iot_domain_id
  display_name            = "${var.name_prefix}-device-b"
  description             = "Digital twin instance for ZPR demo device_b (basic/secret auth)"
  digital_twin_adapter_id = module.device_b_adapter.digital_twin_adapter_tf_id
  auth_id                 = oci_vault_secret.device_b.id
  external_key            = "device-b" # MQTT username the device_b bridge presents
  defined_tags            = {}
}
