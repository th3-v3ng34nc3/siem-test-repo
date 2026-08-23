terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # It's good practice to constrain the version here too
      version = "> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "> 3.0"
    }
  }
}

resource "random_id" "server_prefix" {
  byte_length = 2
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function_${random_id.server_prefix.hex}.zip"
}

resource "aws_lambda_function" "log_shipper" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "${var.accuknox_suffix}_cloudwatch_to_https_shipper"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30

  environment {
    variables = {
      TARGET_URL        = var.cloudwatch_target_url
      CHUNK_SIZE_LIMIT  = var.chunk_size
      LINE_LIMIT        = var.line_limit
      INSECURE_TLS_SKIP = var.insecure_tls
      BASIC_USER        = var.username
      BASIC_PASS        = var.password
    }
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_shipper.function_name
  principal     = "logs.amazonaws.com"


  source_arn = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"
}

resource "aws_cloudwatch_log_subscription_filter" "logging_filter" {
  for_each        = toset(var.log_groups)
  name            = "${var.accuknox_suffix}_https_log_filter"
  log_group_name  = each.value
  filter_pattern  = ""
  destination_arn = aws_lambda_function.log_shipper.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.accuknox_suffix}_log_shipper_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}