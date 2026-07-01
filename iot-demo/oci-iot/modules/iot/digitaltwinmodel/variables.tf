# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
############################
# Variable Block - IoT
# Create IoT Digital Twin Model
############################

variable "display_name" {
  type        = string
  description = "The display name you assign to the Digital Twin Model during creation.  "
  default     = null
}

variable "description" {
  type        = string
  description = "The description you assign to the Digital Twin Model. Does not have to be unique, and it's changeable. "
  default     = null
}

variable "iot_domain_id" {
  type        = string
  description = "The Domain id to which the Digital Twin Model is associated."
  default     = null
}

variable "spec" {
  type        = string
  description = "The specification of the digital twin model (DTDL)."
  default     = null
}

variable "defined_tags" {
  # Default to none: OCI auto-applies Oracle-Tags on create anyway, and callers
  # may lack rights to manage that namespace. Pass a map explicitly only if you can.
  type    = map(any)
  default = {}
}

variable "freeform_tags" {
  type    = map(any)
  default = {}
}
