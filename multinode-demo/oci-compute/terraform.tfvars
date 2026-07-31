# Multinode demo uses its OWN compartment (do NOT reuse iot-demo's OCID).
# OCIDs are identifiers, not secrets; the API key + passphrase stay in ~/.oci/config.

region         = "us-ashburn-1"
compartment_id = "ocid1.compartment.oc1..aaaaaaaayicy4pk637nctytdfvamd4fe4jbzhqnexhych7zpnqp5wsvjrhpq"

# TODO: tighten operator_cidr to your laptop's public IP /32 before a real run.
# operator_cidr = "x.x.x.x/32"
