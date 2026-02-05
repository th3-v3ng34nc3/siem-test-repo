output "access_key_id" {
  value = aws_iam_access_key.bucket_admin.id
  sensitive = true
}

output "secret_access_key" {
  value     = aws_iam_access_key.bucket_admin.secret
  sensitive = true
}

output "bucket_names" {
  description = "The names of the S3 buckets created"
  value       = aws_s3_bucket.prefixed_buckets[*].bucket
}