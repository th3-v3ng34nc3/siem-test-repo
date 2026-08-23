# Generate a unique 5-character lowercase alphanumeric suffix
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

# --- AWS Config itself: bucket, recorder, delivery channel ---------------

resource "aws_s3_bucket" "config_bucket" {
  bucket = "${var.accuknox_suffix}-bucket-${random_string.suffix.result}"
}

resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config_bucket.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config_bucket.arn}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

resource "aws_iam_role" "config_role" {
  name = "${var.accuknox_suffix}-config-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "recorder" {
  name     = "${var.accuknox_suffix}-recorder"
  role_arn = aws_iam_role.config_role.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "channel" {
  name           = "${var.accuknox_suffix}-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket
  depends_on     = [aws_config_configuration_recorder.recorder]
}

resource "aws_config_configuration_recorder_status" "recorder_status" {
  name       = aws_config_configuration_recorder.recorder.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.channel]
}

# --- Lambda Function -------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda.py"
  output_path = "lambda_payload.zip"
}

resource "aws_lambda_function" "config_forwarder" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "${var.accuknox_suffix}-log-forwarder-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda.handler"
  runtime       = "python3.9"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  environment {
    variables = {
      TARGET_URL        = var.target_url
      BASIC_USER        = var.username
      BASIC_PASS        = var.password
      INSECURE_TLS_SKIP = var.insecure_tls
      CHUNK_SIZE_LIMIT  = var.chunk_size
      LINE_LIMIT        = var.line_limit
    }
  }
  depends_on = [
    aws_iam_role.lambda_exec,
  ]
}

# --- S3 Trigger & Permissions ----------------------------------------------

resource "aws_lambda_permission" "s3_trigger_permission" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.config_forwarder.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.config_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notif" {
  bucket = aws_s3_bucket.config_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.config_forwarder.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.s3_trigger_permission,
    aws_lambda_function.config_forwarder
  ]
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.accuknox_suffix}-lambda-exec-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${var.accuknox_suffix}-s3-read-policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.config_bucket.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_logging" {
  name = "${var.accuknox_suffix}-lambda-logging-policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.config_forwarder.function_name}"
  retention_in_days = 3
}

output "lambda_function_name" {
  value = aws_lambda_function.config_forwarder.function_name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "config_bucket_name" {
  value = aws_s3_bucket.config_bucket.bucket
}

output "config_delivery_channel_name" {
  value = aws_config_delivery_channel.channel.name
}
