# Generate a unique 5-character lowercase alphanumeric suffix
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

# 1. S3 Bucket for Logs
resource "aws_s3_bucket" "log_bucket" {
  bucket        = "${var.accuknox_suffix}-bucket-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    id     = "accuknox-retention-policy"
    status = "Enabled"
    expiration {
      days = 14
    }
  }
  depends_on = [aws_s3_bucket.log_bucket]
}

# 2. S3 Bucket Policy (Required for CloudTrail to function)
resource "aws_s3_bucket_policy" "ct_policy" {
  bucket = aws_s3_bucket.log_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.log_bucket.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.log_bucket.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

# 3. Multi-Region CloudTrail
resource "aws_cloudtrail" "management_trail" {
  name                          = "mgmt-api-trail-${random_string.suffix.result}"
  s3_bucket_name                = aws_s3_bucket.log_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.ct_policy]
}

# 4. Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda.py"
  output_path = "lambda_payload.zip"
}

resource "aws_lambda_function" "log_forwarder" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.accuknox_suffix}-log-forwarder-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda.handler"
  runtime       = "python3.9"

  environment {
    variables = {
      TARGET_URL = var.target_url
      BASIC_USER = var.username
      BASIC_PASS = var.password
      INSECURE_TLS_SKIP = var.insecure_tls
    }
  }
  depends_on = [
    aws_iam_role.lambda_exec,
  ]
}

# 5. S3 Trigger & Permissions
resource "aws_lambda_permission" "s3_trigger_permission" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_forwarder.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.log_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notif" {
  bucket = aws_s3_bucket.log_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.log_forwarder.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.s3_trigger_permission,
    aws_lambda_function.log_forwarder
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
      Resource = "${aws_s3_bucket.log_bucket.arn}/*"
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
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        # Restricting to the specific log group for this function is best practice
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Explicitly defining the Log Group in Terraform allows for better cleanup
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.log_forwarder.function_name}"
  retention_in_days = 3 # Keeps your CloudWatch costs down
}