output "device_a_public_ip" {
  value = oci_core_instance.device_a.public_ip
}

output "device_b_public_ip" {
  value = oci_core_instance.device_b.public_ip
}

output "zpr_core_public_ip" {
  value = oci_core_instance.zpr_core.public_ip
}

output "device_a_private_ip" {
  value = oci_core_instance.device_a.private_ip
}

output "device_b_private_ip" {
  value = oci_core_instance.device_b.private_ip
}

output "zpr_core_private_ip" {
  description = "The address device instances dial for the ZPR substrate (node self_addr:5000)."
  value       = oci_core_instance.zpr_core.private_ip
}

# Convenience: ready-to-paste SSH commands for post-init (private key = pub minus .pub).
output "ssh_commands" {
  value = {
    device_a = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} opc@${oci_core_instance.device_a.public_ip}"
    device_b = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} opc@${oci_core_instance.device_b.public_ip}"
    zpr_core = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} opc@${oci_core_instance.zpr_core.public_ip}"
  }
}
