############################
# Provider / placement
############################
variable "region" {
  type        = string
  description = "OCI region (matches ~/.oci/config)."
  default     = "us-ashburn-1"
}

variable "compartment_id" {
  type        = string
  description = "Compartment where all compute + network resources live. ZPR-IoT-Demo."
}

variable "availability_domain" {
  type        = string
  description = "AD to launch instances in. Defaults resolved via data source if empty."
  default     = ""
}

############################
# Networking
############################
variable "vcn_cidr" {
  type        = string
  description = "CIDR for the demo VCN."
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR for the single public subnet all instances share."
  default     = "10.0.0.0/24"
}

variable "operator_cidr" {
  type        = string
  description = "Source CIDR allowed to SSH (your laptop's public IP /32). 0.0.0.0/0 for open demo."
  default     = "0.0.0.0/0" # TODO: tighten to operator /32 for a real run
}

variable "zpr_substrate_port" {
  type        = number
  description = "UDP port the ZPR node listens on (node self_addr). Substrate is UDP."
  default     = 5000
}

############################
# Compute
############################
variable "instance_shape" {
  type        = string
  description = "Compute shape for all three instances."
  default     = "VM.Standard.E5.Flex"
}

variable "instance_ocpus" {
  type    = number
  default = 1
}

variable "instance_memory_gb" {
  type    = number
  default = 4
}

variable "instance_image_id" {
  type        = string
  description = "Oracle Linux 9 image OCID for the shape/region. TODO: confirm current image."
  default     = "ocid1.image.oc1.iad.aaaaaaaa4n6qszi7i4u4vpphmxnv5djj26hewj5gtdfw2z7f7mchb6xue7ea"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the demo SSH public key injected into all instances."
  default     = "~/.ssh/zpr-demo.pub"
}

variable "zpr_dir" {
  type        = string
  description = "On-instance base directory for ZPR binaries/configs/certs."
  default     = "/opt/zpr"
}

############################
# Artifacts (staged in Object Storage)
############################
# No defaults: build-in-ol9.sh writes these three into binaries.auto.tfvars, which
# tofu loads automatically. A default here would let a stale path survive a change
# to the build output location and silently upload a previous build's binary.
variable "ph_binary_path" {
  type        = string
  description = "Path to the ph binary. OL9-built release (glibc 2.34); set by build-in-ol9.sh."
}

variable "vs_binary_path" {
  type        = string
  description = "Path to the vs binary. OL9-built release (glibc 2.34); set by build-in-ol9.sh."
}

variable "vsapikey_binary_path" {
  type        = string
  description = "Path to the vsapikey binary (generates the admin API key at boot). OL9-built."
}

variable "par_expiry" {
  type        = string
  description = "Absolute expiry (RFC3339) for the artifact pre-authenticated request. Bump as needed."
  default     = "2027-01-01T00:00:00Z"
}

############################
# Naming
############################
variable "name_prefix" {
  type        = string
  description = "Prefix applied to created resource names."
  default     = "zpr-iot-demo"
}
