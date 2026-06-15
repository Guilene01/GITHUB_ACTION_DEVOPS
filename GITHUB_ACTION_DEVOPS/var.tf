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

variable "sonarcloud_token" {
  description = "SonarCloud token used by the GitHub Actions pipeline. Leave empty to populate the secret later via the AWS CLI."
  type        = string
  default     = ""
  sensitive   = true
}
