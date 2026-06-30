# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
############################
# Output Block - Iot
# Create Digital Twin Model
############################

output "digital_twin_model_tf_id" {
  value = oci_iot_digital_twin_model.digital_twin_model.id
}
