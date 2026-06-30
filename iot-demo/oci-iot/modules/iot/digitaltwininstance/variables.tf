# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
############################
# Variable Block - IoT
# Create digital twin instance
############################
variable "display_name" {
  type        = string
  description = "The dosplay name you assign to the domain group during creation."
  default     = null
}

variable "description" {
  type        = string
  description = "The description you assign to the domain group. Does not have to be unique, and it's changeable."
  default     = null
}

variable "iot_domain_id" {
  type        = string
  description = "The Domain id to which the Digital Twin Instance is associated."
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

variable "digital_twin_adapter_id" {
  type        = string
  description = "The OCID of the digital twin adapter"
  default     = null
}

variable "auth_id" {
  type        = string
  description = "The OCID of the resource (like VaultSecret, ClientCertificate etc.,) used to authenticate the digital twin instance"
  default     = null
}

variable "external_key" {
  type        = string
  description = "A unique identifier for the physical entity (typically an IoT device) represented by the digital twin instance"
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
