output "ssh_connection" {
  value = "ssh -i ${local_file.ssh_key.filename} ec2-user@${aws_instance.main-server.public_dns}"
}

output "artifactory_url" {
  value = "http://${aws_instance.main-server.public_ip}:8082"
}

output "vault_url" {
  value = "http://${aws_instance.main-server.public_ip}:8200"
}

output "vault_key_file" {
  value = "vaultkey.txt"
}

output "github_actions_role_arn" {
  description = "Put this in your GitHub repo secret AWS_OIDC_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "jfrog_default_credentials" {
  description = "Default JFrog Artifactory login — change the password on first login"
  value       = "username: admin  |  password: password"
}
