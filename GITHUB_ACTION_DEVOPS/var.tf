variable "aws_region" {
  description = "AWS region to deploy into"
  default     = "us-east-1"
  type        = string
}

variable "profile" {
  description = "AWS CLI profile to use"
  default     = "default"
  type        = string
}

variable "aws_instance_type_server" {
  description = "EC2 instance type for the tools server"
  default     = "t2.large"
  type        = string
}

# Secret that will be used to connect to the JFrog server from the tools instance.
variable "jfrog_secret_username_and_password" {
  description = "JFrog Artifactory admin username and password, e.g. [\"admin\", \"<password>\"]"
  type        = list(string)
  sensitive   = true
}

variable "jfrog_secret_token" {
  description = "JFrog Artifactory access token"
  type        = string
  sensitive   = true
}

# Used by oidc.tf to scope the GitHub Actions OIDC role to this repo's main branch.
variable "github_org" {
  description = "Your GitHub username or organization (e.g. \"octocat\")"
  type        = string
}

variable "github_repo" {
  description = "The repository that will run the GitHub Actions workflow (e.g. \"my-app\")"
  type        = string
}
