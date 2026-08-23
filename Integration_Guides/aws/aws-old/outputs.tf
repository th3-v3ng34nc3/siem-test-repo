output "stackset_name" {
  description = "Name of the created CloudFormation StackSet"
  value       = aws_cloudformation_stack_set.accuknox_siem.name
}

output "stackset_id" {
  description = "ID of the created CloudFormation StackSet"
  value       = aws_cloudformation_stack_set.accuknox_siem.stack_set_id
}

output "stackset_arn" {
  description = "ARN of the created CloudFormation StackSet"
  value       = aws_cloudformation_stack_set.accuknox_siem.arn
}

output "deployed_regions" {
  description = "Regions where the SIEM stack was deployed"
  value       = var.target_regions
}

output "deployment_summary" {
  description = "Summary of the SIEM deployment"
  value = {
    stackset_name           = aws_cloudformation_stack_set.accuknox_siem.name
    lambda_code_bucket      = var.lambda_code_s3_bucket
    lambda_code_key         = var.lambda_code_s3_key
    siem_host              = var.siem_host
    account_filter_type    = var.account_filter_type
    target_accounts        = var.target_accounts
    target_regions         = var.target_regions
    organization_id        = var.org_id
  }
}