variable "aws_profile" {
  description = "AWS CLI profile (e.g. SSO profile Devan). Matches `aws configure list-profiles`."
  type        = string
  default     = "Devan"
}

variable "region" {
  description = "AWS region (US users → us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Hackathon resource prefix, e.g. hackthon-k9-intern-devan"
  type        = string
  default     = "hackthon-k9-intern-devan"
}
