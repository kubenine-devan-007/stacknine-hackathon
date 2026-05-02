locals {
  common_tags = {
    ManagedBy = "terraform"
    Stack     = "stacknine-invoice-processor"
  }

  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
  image_main   = "${local.ecr_registry}/${var.name_prefix}-main-backend-ecr:latest"
  image_ext    = "${local.ecr_registry}/${var.name_prefix}-extractor-ecr:latest"
  image_parse  = "${local.ecr_registry}/${var.name_prefix}-parser-ecr:latest"
}
