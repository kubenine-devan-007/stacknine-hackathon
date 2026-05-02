data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = abspath("${path.module}/../lambda/handler.py")
  output_path = "${path.module}/lambda_s3_trigger.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-s3-trigger"
  retention_in_days = 7
}

resource "aws_lambda_function" "s3_trigger" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.name_prefix}-s3-trigger"
  role          = aws_iam_role.lambda_s3.arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  timeout       = 60

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy.lambda_ssm,
    aws_cloudwatch_log_group.lambda
  ]
}

resource "aws_lambda_function_event_invoke_config" "s3_trigger" {
  function_name = aws_lambda_function.s3_trigger.function_name

  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
