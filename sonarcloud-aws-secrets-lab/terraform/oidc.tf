# This lets GitHub Actions log in to AWS without storing any AWS password/keys
# in GitHub. AWS trusts a short-lived token that GitHub generates for each run.

# 1. Reuse the GitHub OIDC provider that already exists in this AWS account.
# NOTE: an AWS account can only have ONE provider for
# token.actions.githubusercontent.com. If this account doesn't have one yet,
# replace this data source with the aws_iam_openid_connect_provider resource
# (see README) to create it instead.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# 2. A role that GitHub Actions is allowed to "become" — but only when the
# workflow is running for YOUR repo's main branch.
resource "aws_iam_role" "github_actions" {
  name = "github-actions-sonarcloud-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

# 3. The role can ONLY read the one SonarCloud secret — nothing else.
resource "aws_iam_role_policy" "read_sonarcloud_token" {
  name = "read-sonarcloud-token"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.sonarcloud_token.arn
      }
    ]
  })
}
