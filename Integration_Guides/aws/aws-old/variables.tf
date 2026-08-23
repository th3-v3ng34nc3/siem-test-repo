variable "aws_profile" {
  description = "AWS profile to use for authentication"
  type        = string
  default     = "default"
}

variable "aws_region" {
  description = "Primary AWS region for StackSet management"
  type        = string
  default     = "us-east-2"
}

variable "target_regions" {
  description = "List of regions to deploy the SIEM stack"
  type        = list(string)
  default     = ["us-east-2"]
}

variable "stackset_name" {
  description = "Name of the CloudFormation StackSet"
  type        = string
  default     = "AccuKnoxSIEMDeployment"
}

variable "org_id" {
  description = "AWS Organization ID"
  type        = string
}

variable "management_account_id" {
  description = "AWS Organization management account ID"
  type        = string
}

variable "account_filter_type" {
  description = "Account targeting filter type: INCLUDE, EXCLUDE, or ALL"
  type        = string
  default     = "ALL"
  validation {
    condition     = contains(["INCLUDE", "EXCLUDE", "ALL"], var.account_filter_type)
    error_message = "Account filter type must be one of: INCLUDE, EXCLUDE, ALL."
  }
}

variable "target_accounts" {
  description = "List of AWS account IDs to include or exclude based on account_filter_type"
  type        = list(string)
  default     = []
}

# SIEM Configuration
variable "siem_username" {
  description = "AccuKnox SIEM username"
  type        = string
  default     = "admin"
}

variable "siem_password" {
  description = "AccuKnox SIEM password"
  type        = string
  sensitive   = true
}

variable "siem_host" {
  description = "AccuKnox SIEM host"
  type        = string
  default     = "siem.accuknox.com"
}

variable "siem_port" {
  description = "AccuKnox SIEM port"
  type        = string
  default     = "9200"
}

# Lambda Deployment Configuration
variable "lambda_code_s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
  default     = "accuknox-siem-lambda-code"
}

variable "lambda_code_s3_key" {
  description = "S3 key for the Lambda deployment package"
  type        = string
  default     = "accuknox-siem-cloudtrail-processor.zip"
}

# Tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Project     = "AccuKnox-SIEM"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}