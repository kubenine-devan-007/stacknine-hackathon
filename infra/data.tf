data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_kms_key" "ssm_secrets" {
  key_id = "alias/aws/ssm"
}
