variable "budget_alert_email" {
  description = "Email address for the aws budget alert"
  type        = string
}

variable "git_sha" {
  description = "Git commit SHA deployed to EC2"
  type        = string
}