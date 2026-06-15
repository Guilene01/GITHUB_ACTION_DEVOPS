output "ssh_connexion" {
  value = "ssh -i ${local_file.ssh_key.filename} ec2-user@${aws_instance.main-server.public_dns}"
}

output "JFROG_URL" {
  value = "http://${aws_instance.main-server.public_ip}:8082"
}

output "HASHICORP_VAULT_URL" {
  value = "http://${aws_instance.main-server.public_ip}:8200"
}

output "vault_key_file" {
  value = "vaultkey.txt"
}
