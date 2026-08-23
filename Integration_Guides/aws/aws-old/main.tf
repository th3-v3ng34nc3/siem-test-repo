terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# CloudFormation StackSet for AccuKnox SIEM deployment
resource "aws_cloudformation_stack_set" "accuknox_siem" {
  name             = var.stackset_name
  description      = "AccuKnox SIEM CloudTrail integration"
  permission_model = "SERVICE_MANAGED"
  
  capabilities = ["CAPABILITY_NAMED_IAM"]
  
  template_body = file("${path.module}/accuknox-siem-deploy.yaml")
  
  parameters = {
    OrgId                  = var.org_id
    AccuknoxSIEMUsername   = var.siem_username
    AccuKnoxSIEMPassword   = var.siem_password
    AccuKnoxSIEMHost       = var.siem_host
    AccuKnoxSIEMPort       = var.siem_port
    LambdaCodeS3Bucket     = var.lambda_code_s3_bucket
    LambdaCodeS3Key        = var.lambda_code_s3_key
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  operation_preferences {
    region_concurrency_type    = "PARALLEL"
    max_concurrent_percentage  = 100
    failure_tolerance_percentage = 90
  }

  lifecycle {
    ignore_changes = [
      administration_role_arn,
    ]
  }

  tags = var.tags
}

# StackSet deployment using organizational unit targeting
resource "aws_cloudformation_stack_set_instance" "accuknox_siem" {
  count = length(var.target_regions)
  
  stack_set_name = aws_cloudformation_stack_set.accuknox_siem.name
  region         = var.target_regions[count.index]
  
  deployment_targets {
    organizational_unit_ids = [var.org_id]
    account_filter_type     = var.account_filter_type == "EXCLUDE" ? "DIFFERENCE" : (var.account_filter_type == "INCLUDE" ? "INTERSECTION" : "NONE")
    accounts               = var.account_filter_type != "ALL" ? var.target_accounts : null
  }

  operation_preferences {
    region_concurrency_type    = "PARALLEL"
    max_concurrent_percentage  = 100
    failure_tolerance_percentage = 90
  }

  depends_on = [aws_cloudformation_stack_set.accuknox_siem]
}
