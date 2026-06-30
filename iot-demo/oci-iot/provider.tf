terraform {
  required_version = ">= 1.6.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 8.7.0" # IoT digital-twin resources require a recent provider
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# Auth comes from ~/.oci/config (profile DEFAULT) — same creds the OCI CLI uses.
# No secrets live in this repo; the API private key + passphrase stay in ~/.oci.
provider "oci" {
  config_file_profile = "DEFAULT"
  region              = var.region
}
