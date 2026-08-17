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
  description = "Compartment where all compute + network resources live."
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

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the demo SSH public key injected into all instances."
  default     = "~/.ssh/zpr-demo.pub"
}

############################
# Naming
############################
variable "name_prefix" {
  type        = string
  description = "Prefix applied to created resource names."
  default     = "zpr-multinode"
}
