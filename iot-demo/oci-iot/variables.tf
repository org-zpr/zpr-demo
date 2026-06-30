############################
# Provider / tenancy
############################
variable "region" {
  type        = string
  description = "OCI region (matches ~/.oci/config)."
  default     = "us-ashburn-1"
}

variable "tenancy_ocid" {
  type        = string
  description = "Tenancy OCID. Used for the dynamic group (tenancy-level resource)."
}

variable "compartment_id" {
  type        = string
  description = "Compartment where all demo resources (vault, CA, cert, IoT) live. ZPR-IoT-Demo."
}

############################
# Existing IoT domain (built by IT — referenced, NOT created)
############################
variable "iot_domain_id" {
  type        = string
  description = "OCID of the existing ZPR-Demo-Domain. The model/adapter/instance attach to it."
}

variable "iot_device_host" {
  type        = string
  description = "The domain's MQTT device-host endpoint (from `oci iot domain get`). Surfaced as an output for the mosquitto bridge config."
  default     = "oglu6kuqdp5aa.device.iot.us-ashburn-1.oci.oraclecloud.com"
}

############################
# Naming
############################
variable "name_prefix" {
  type        = string
  description = "Prefix applied to created resource names."
  default     = "zpr-iot-demo"
}
