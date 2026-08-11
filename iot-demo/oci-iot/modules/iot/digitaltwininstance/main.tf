# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
#############################
# Resource Block - IoT
# Create Digital Twin Instance
#############################

resource "oci_iot_digital_twin_instance" "digital_twin_instance" {

  #Required
  iot_domain_id = var.iot_domain_id
  display_name  = var.display_name
  description   = var.description
  auth_id       = var.auth_id
  external_key  = var.external_key

  #Optional
  digital_twin_model_id   = var.digital_twin_model_id
  digital_twin_adapter_id = var.digital_twin_adapter_id
  defined_tags            = var.defined_tags
  freeform_tags           = var.freeform_tags

  # OCI auto-applies Oracle-Tags defined tags on create; this user can't manage
  # that namespace, so ignore drift on defined_tags to avoid a failing update.
  lifecycle {
    ignore_changes = [defined_tags]
  }
}
