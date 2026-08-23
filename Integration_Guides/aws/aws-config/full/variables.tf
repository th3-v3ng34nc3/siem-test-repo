variable "accuknox_suffix" {
  type    = string
  default = "accuknox-awsconfig-collector"
}

# No default on purpose: S3 event notifications can only invoke a Lambda in
# the same region as the bucket, so this must always be set explicitly to
# the region you want AWS Config, the S3 bucket, and the Lambda created in.
variable "region" {
  type        = string
  description = "AWS region to create the S3 bucket, AWS Config recorder/delivery channel, and Lambda in."
}

variable "username" {
  type      = string
  sensitive = true
}

variable "password" {
  type      = string
  sensitive = true
}

variable "target_url" {
  type = string
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
