# Centralized secrets for the CI/CD toolchain, stored in AWS Secrets Manager so
# GitHub Actions can retrieve them at runtime (via OIDC) instead of relying on
# plaintext values in tfvars or hardcoded GitHub repo secrets.

resource "aws_secretsmanager_secret" "jfrog_credentials" {
  name        = "cicd/jfrog-credentials"
  description = "JFrog Artifactory credentials used by Vault and the GitHub Actions pipeline"
}

resource "aws_secretsmanager_secret_version" "jfrog_credentials" {
  secret_id = aws_secretsmanager_secret.jfrog_credentials.id
  secret_string = jsonencode({
    username = var.jfrog_secret_username_and_password[0]
    password = var.jfrog_secret_username_and_password[1]
    token    = var.jfrog_secret_token
  })
}

resource "aws_secretsmanager_secret" "sonarcloud_token" {
  name        = "cicd/sonarcloud-token"
  description = "SonarCloud token used by the GitHub Actions pipeline for code analysis"
}

# The SonarCloud token is generated manually in the SonarCloud UI (see README),
# so the secret version is only created once a value is supplied. If left empty,
# populate it later with:
#   aws secretsmanager put-secret-value --secret-id cicd/sonarcloud-token \
#     --secret-string '{"SONAR_TOKEN":"<token>"}'
resource "aws_secretsmanager_secret_version" "sonarcloud_token" {
  count         = var.sonarcloud_token != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.sonarcloud_token.id
  secret_string = jsonencode({
    SONAR_TOKEN = var.sonarcloud_token
  })
}
