# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
#############################
# Resource Block - IoT
# Create Digital Twin Adapter
#############################

resource "oci_iot_digital_twin_adapter" "digital_twin_adapter" {

  #Required
  iot_domain_id = var.iot_domain_id

  #Optional
  display_name                = var.display_name
  description                 = var.description
  digital_twin_model_id       = var.digital_twin_model_id
  digital_twin_model_spec_uri = var.digital_twin_model_spec_uri
  defined_tags                = var.defined_tags
  freeform_tags               = var.freeform_tags

  dynamic "inbound_envelope" {
    for_each = var.inbound_envelope != null ? [var.inbound_envelope] : []
    content {
      reference_endpoint = inbound_envelope.value.referenceEndpoint

      dynamic "envelope_mapping" {
        for_each = contains(keys(inbound_envelope.value), "envelopeMapping") ? { envelope_mapping = true } : {}
        content {
          time_observed = try(inbound_envelope.value.envelopeMapping.timeObserved, null)
        }
      }

      dynamic "reference_payload" {
        for_each = contains(keys(inbound_envelope.value), "referencePayload") ? { reference_payload = true } : {}
        content {
          data        = inbound_envelope.value.referencePayload.data
          data_format = inbound_envelope.value.referencePayload.dataFormat
        }
      }
    }
  }

  dynamic "inbound_routes" {
    for_each = var.inbound_routes != null ? var.inbound_routes : []
    content {
      condition       = inbound_routes.value.condition
      description     = try(inbound_routes.value.description, null)
      payload_mapping = try(inbound_routes.value.payloadMapping, null)

      dynamic "reference_payload" {
        for_each = contains(keys(inbound_routes.value), "referencePayload") ? { reference_payload = true } : {}
        content {
          data        = inbound_routes.value.referencePayload.data
          data_format = inbound_routes.value.referencePayload.dataFormat
        }
      }
    }
  }

  # OCI auto-applies Oracle-Tags defined tags on create; this user can't manage
  # that namespace, so ignore drift on defined_tags to avoid a failing update.
  lifecycle {
    ignore_changes = [defined_tags]
  }
}
