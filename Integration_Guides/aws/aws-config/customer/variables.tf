variable "accuknox_suffix" {
  type    = string
  default = "accuknox-awsconfig-collector"
}

# No default on purpose: S3 event notifications can only invoke a Lambda in
# the same region as the bucket, so this must always be set explicitly to
# match bucket_name/bucket_arn's actual region rather than silently
# defaulting to a region that may not match.
variable "region" {
  type        = string
  description = "AWS region the existing S3 bucket (bucket_name/bucket_arn) is in."
}

variable "username" {
  type      = string
  sensitive = true
}

variable "password" {
  type      = string
  sensitive = true
}

variable "bucket_arn" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "target_url" {
  type = string
}

# Scopes the S3 trigger to AWS Config's own files, e.g.
# "AWSLogs/111122223333/Config/" - important when the bucket is
# shared with CloudTrail or other log deliveries, so this Lambda
# only fires on AWS Config's ConfigSnapshot / ConfigHistory objects.
variable "config_key_prefix" {
  type    = string
  default = ""
}

variable "chunk_size" {
  type = string
  # defults to 3MB in lambda code
  default = ""
}

variable "line_limit" {
  type = string
  # defults to 1000 lines in lambda code
  default = ""
}

variable "insecure_tls" {
  type = string
  # defults to false in lambda code
  # can either be false or true // as strings
  default = ""
}

# AWS Config snapshot files (full account inventory) can be far
# larger than a single CloudTrail delta and are decompressed
# entirely in memory, so both of these are explicit here rather
# than left at AWS's defaults (128MB / 3s).
variable "lambda_memory_mb" {
  type    = number
  default = 512
}

variable "lambda_timeout_seconds" {
  type    = number
  default = 120
}
