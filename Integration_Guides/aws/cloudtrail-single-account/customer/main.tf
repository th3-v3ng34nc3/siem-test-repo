# Generate a unique 5-character lowercase alphanumeric suffix
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
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
      TARGET_URL        = var.target_url
      BASIC_USER        = var.username
      BASIC_PASS        = var.password
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
  source_arn    = var.bucket_arn
}

resource "aws_s3_bucket_notification" "bucket_notif" {
  bucket = var.bucket_name

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
      Resource = "${var.bucket_arn}/*"
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