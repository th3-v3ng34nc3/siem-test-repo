provider "aws" {
  region = "us-west-1"
  profile = "prd"
  default_tags {
    tags = {
      Env   = "prod"
      owner = "us-prod-siem-v2"
    }
  }
}


resource "aws_s3_bucket" "prefixed_buckets" {
  count  = 3
  bucket = "${var.bucket_prefix}-bucket-${count.index + 1}"


}
resource "aws_s3_bucket_versioning" "versioning_example" {
  count  = 3
  bucket = aws_s3_bucket.prefixed_buckets[count.index].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_user" "bucket_admin" {
  name = "${var.bucket_prefix}-admin"
}

resource "aws_iam_user_policy" "s3_full_access" {
  name = "${var.bucket_prefix}-s3-access"
  user = aws_iam_user.bucket_admin.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "s3:*"
        Effect = "Allow"
        Resource = flatten([
          for b in aws_s3_bucket.prefixed_buckets : [
            b.arn,       # Access to the bucket itself (ListBucket)
            "${b.arn}/*" # Access to all objects inside (Put/Get/Delete)
          ]
        ])
      }
    ]
  })
}

resource "aws_iam_access_key" "bucket_admin" {
  user = aws_iam_user.bucket_admin.name
}