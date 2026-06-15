variable "aws_region" {
  description = "AWS region to create resources in"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "Your GitHub username or organization (e.g. \"octocat\")"
  type        = string
}

variable "github_repo" {
  description = "The repository that will run the GitHub Actions workflow (e.g. \"my-app\")"
  type        = string
}

variable "secret_name" {
  description = "Name of the AWS Secrets Manager secret that stores the SonarCloud token"
  type        = string
  default     = "sonarcloud/token"
}

variable "sonarcloud_token" {
  description = "Your SonarCloud token. Leave empty and set it later with the AWS CLI (see README step 4)."
  type        = string
  default     = ""
  sensitive   = true
}
