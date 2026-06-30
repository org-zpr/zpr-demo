# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
############################
# Variable Block - IoT
# Create IoT Digital Twin Adapter
############################

variable "display_name" {
  type        = string
  description = "The display name you assign to the Digital Twin Adapter during creation."
  default     = null
}

variable "description" {
  type        = string
  description = "The description you assign to the Digital Twin Adapter."
  default     = null
}

variable "iot_domain_id" {
  type        = string
  description = "The Domain id to which the Digital Twin Adapter is associated."
  default     = null
}

variable "digital_twin_model_id" {
  type        = string
  description = "The OCID of the digital twin model"
  default     = null
}

variable "digital_twin_model_spec_uri" {
  type        = string
  description = "The URI of the digital twin model specification"
  default     = null
}

variable "inbound_envelope" {
  description = "Decoded JSON envelope config (camelCase keys: referenceEndpoint, envelopeMapping, referencePayload)"
  type        = any
  default     = null
}

variable "inbound_routes" {
  description = "Decoded JSON routes config (camelCase keys: condition, description, payloadMapping, referencePayload)"
  type        = any
  default     = null
}

variable "defined_tags" {
  type = map(any)
  default = { "Oracle-Tags.CreatedOn" = "$${oci.datetime}",
    "Oracle-Tags.CreatedBy" = "$${iam.principal.name}"
  }
}

variable "freeform_tags" {
  type    = map(any)
  default = {}
}
