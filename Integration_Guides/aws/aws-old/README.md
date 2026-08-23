# AccuKnox SIEM Terraform Deployment

This Terraform configuration deploys the AccuKnox SIEM CloudTrail integration across AWS Organizations using CloudFormation StackSets with S3-based Lambda deployment.

## Architecture

- **CloudFormation StackSet**: Manages deployment across multiple AWS accounts
- **S3-based Lambda**: No ECR setup required - Lambda code deployed from S3
- **CloudTrail Integration**: Automatically processes CloudTrail logs
- **Organization-wide**: Supports INCLUDE/EXCLUDE/ALL account targeting

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform >= 1.0** installed
3. **AWS Organizations** with trusted access enabled for CloudFormation StackSets
4. **Lambda deployment package** uploaded to S3

### Required AWS Permissions

The AWS profile used must have permissions for:

- `cloudformation:*` (StackSet operations)
- `organizations:ListAccounts`
- `organizations:DescribeOrganization`
- `iam:ListRoles`
- `iam:PassRole`

## Setup

1. **Copy and configure variables:**

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your configuration
   ```

2. **Initialize Terraform:**

   ```bash
   terraform init
   ```

3. **Plan deployment:**

   ```bash
   terraform plan
   ```

4. **Deploy:**
   ```bash
   terraform apply
   ```

## Configuration

### Account Targeting Options (SELECT ONLY ONE)

#### Deploy to All Accounts

```hcl
account_filter_type = "ALL"
target_accounts     = []
```

#### Deploy to Specific Accounts Only

```hcl
account_filter_type = "INCLUDE"
target_accounts     = ["111111111111", "222222222222"]
```

#### Deploy to All Except Specific Accounts

```hcl
account_filter_type = "EXCLUDE"
target_accounts     = ["333333333333", "444444444444"]
```

## Monitoring

After deployment, monitor:

- CloudFormation StackSet operations in AWS Console
- Lambda function execution logs in CloudWatch
- CloudTrail log processing in target accounts

## Cleanup

To remove all deployed resources:

```bash
terraform destroy
```

This will:

1. Delete all stack instances across accounts/regions
2. Remove the CloudFormation StackSet
3. Clean up all associated resources

## Troubleshooting

### Common Issues

1. **StackSet Permission Errors**

   - Ensure AWS Organizations trusted access is enabled
   - Verify management account permissions

## Variables Reference

| Variable              | Description                            | Default | Required |
| --------------------- | -------------------------------------- | ------- | -------- |
| `org_id`              | AWS Organization ID                    | -       | Yes      |
| `siem_password`       | AccuKnox SIEM password                 | -       | Yes      |
| `account_filter_type` | Account targeting: ALL/INCLUDE/EXCLUDE | `ALL`   | No       |
