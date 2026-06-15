output "github_actions_role_arn" {
  description = "Put this in your GitHub repo secret AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "secret_name" {
  description = "Name of the AWS Secrets Manager secret holding the SonarCloud token"
  value       = aws_secretsmanager_secret.sonarcloud_token.name
}
