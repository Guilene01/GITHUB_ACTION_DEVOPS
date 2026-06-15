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

output "jfrog_credentials_secret_arn" {
  value = aws_secretsmanager_secret.jfrog_credentials.arn
}

output "sonarcloud_token_secret_arn" {
  value = aws_secretsmanager_secret.sonarcloud_token.arn
}

output "github_actions_role_arn" {
  description = "Put this in your GitHub repo secret AWS_OIDC_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
