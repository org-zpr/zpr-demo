output "public_ips" {
  value = { for k, h in oci_core_instance.host : k => h.public_ip }
}

output "private_ips" {
  value = { for k, h in oci_core_instance.host : k => h.private_ip }
}

# Convenience: ready-to-paste SSH commands (private key = pub minus .pub, user=ubuntu).
output "ssh_commands" {
  value = {
    for k, h in oci_core_instance.host :
    k => "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ubuntu@${h.public_ip}"
  }
}
