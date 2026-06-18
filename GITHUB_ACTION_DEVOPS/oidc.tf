# Lets the GitHub Actions workflow log in to AWS via OIDC (no long-lived AWS
# keys stored in GitHub) and read the secrets created in secrets.tf.

# Reuse the GitHub OIDC provider that already exists in this AWS account.
# NOTE: an AWS account can only have ONE provider for
# token.actions.githubusercontent.com. If this account doesn't have one yet,
# replace this data source with an aws_iam_openid_connect_provider resource:
#   resource "aws_iam_openid_connect_provider" "github" {
#     url             = "https://token.actions.githubusercontent.com"
#     client_id_list  = ["sts.amazonaws.com"]
#     thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
#   }
# and change every data.aws_iam_openid_connect_provider.github.arn below to
# aws_iam_openid_connect_provider.github.arn.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Role that the GitHub Actions pipeline assumes, but only when running on
# this repo's main branch.
resource "aws_iam_role" "github_actions" {
  name = "github-actions-cicd-role"

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

