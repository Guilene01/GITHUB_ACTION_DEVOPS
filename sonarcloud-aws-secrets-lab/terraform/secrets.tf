# The "box" that will hold your SonarCloud token in AWS.
resource "aws_secretsmanager_secret" "sonarcloud_token" {
  name        = var.secret_name
  description = "SonarCloud token used by the GitHub Actions workflow"
}

# Only writes a value into the box if you provided one in terraform.tfvars.
# Otherwise, fill it in later with the AWS CLI (see README step 4).
resource "aws_secretsmanager_secret_version" "sonarcloud_token" {
  count     = var.sonarcloud_token != "" ? 1 : 0
  secret_id = aws_secretsmanager_secret.sonarcloud_token.id
  secret_string = jsonencode({
    SONAR_TOKEN = var.sonarcloud_token
  })
}
