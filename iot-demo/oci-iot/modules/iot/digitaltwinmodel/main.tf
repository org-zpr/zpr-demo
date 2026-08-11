# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
#############################
# Resource Block - IoT
# Create Digital Twin Model
#############################

resource "oci_iot_digital_twin_model" "digital_twin_model" {

  #Required
  iot_domain_id = var.iot_domain_id
  spec          = var.spec

  #Optional
  display_name  = var.display_name
  description   = var.description
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  # OCI auto-applies Oracle-Tags defined tags on create; this user can't manage
  # that namespace, so ignore drift on defined_tags to avoid a failing update.
  lifecycle {
    ignore_changes = [defined_tags]
  }
}
