# Copyright (c) 2024, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
############################
# Output Block - Iot
# Create Digital Twin Instance
############################

output "digital_twin_instance_tf_id" {
  value = oci_iot_digital_twin_instance.digital_twin_instance.id
}
