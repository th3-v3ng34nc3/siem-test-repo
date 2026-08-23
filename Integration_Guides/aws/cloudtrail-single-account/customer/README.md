# AWS CloudTrail Single-Account CDR — Customer Variant

This Terraform module deploys a **CloudTrail-to-SIEM log forwarding pipeline** for a single AWS account using an **existing S3 bucket and CloudTrail trail**. A Lambda function is triggered by S3 object creation events, decompresses the CloudTrail log files, chunks them, and forwards them to an AccuKnox CDR / SIEM endpoint via HTTPS.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           AWS Account                                    │
│                                                                          │
│  ┌──────────────┐     ┌──────────────────┐     ┌─────────────────────┐ │
│  │  CloudTrail   │────▶│  S3 Bucket        │────▶│  Lambda Function    │ │
│  │  (existing)   │     │  (existing)       │     │  (log forwarder)    │ │
│  └──────────────┘     └──────────────────┘     └─────────┬───────────┘ │
│                                                           │             │
└───────────────────────────────────────────────────────────┼─────────────┘
                                                            │
                                                            ▼ HTTPS POST
                                                  ┌─────────────────────┐
                                                  │   AccuKnox CDR /    │
                                                  │      SIEM           │
                                                  └─────────────────────┘
```

---

## What This Module Creates

| Resource | Description |
|---|---|
| **Lambda Function** | Python function that reads, decompresses, chunks, and forwards CloudTrail logs |
| **Lambda IAM Role** | Execution role with S3 read + CloudWatch Logs permissions |
| **Lambda IAM Policies** | `s3:GetObject` on the bucket, plus CloudWatch Logs write access |
| **S3 Bucket Notification** | Triggers the Lambda on every `s3:ObjectCreated:*` event |
| **Lambda Permission** | Allows S3 to invoke the Lambda function |
| **CloudWatch Log Group** | Stores Lambda execution logs (3-day retention) |

---

## Prerequisites

### 1. Existing Resources (Customer-Owned)

This module assumes you **already have** the following in your AWS account:

| Resource | Details |
|---|---|
| **S3 Bucket** | Receiving CloudTrail log files (gzip-compressed JSON) |
| **CloudTrail Trail** | Logging to the above S3 bucket |

> ⚠️ This module does **not** create the S3 bucket or CloudTrail trail. If you need those as well, use the [full variant](../full/) instead.

### 2. AWS Credentials

Ensure your AWS CLI / environment is authenticated:

```bash
# Option 1: Named profile
export AWS_PROFILE=your-profile

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=us-west-1
```

### 3. Tools Required

| Tool | Minimum Version | Installation |
|---|---|---|
| [Terraform](https://www.terraform.io/downloads) | >= 1.0 | `brew install terraform` (macOS) |
| [AWS CLI](https://aws.amazon.com/cli/) | Latest | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |

### 4. AWS Permissions

The IAM user/role running Terraform needs these permissions:

| Permission | Purpose |
|---|---|
| `lambda:CreateFunction`, `lambda:UpdateFunctionCode`, `lambda:UpdateFunctionConfiguration`, `lambda:DeleteFunction` | Manage the Lambda function |
| `lambda:AddPermission`, `lambda:RemovePermission` | Allow S3 to invoke Lambda |
| `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`, `iam:PutRolePolicy` | Create and manage the Lambda execution role |
| `s3:PutBucketNotification`, `s3:GetBucketNotification` | Configure S3 event notifications |
| `logs:CreateLogGroup`, `logs:PutRetentionPolicy` | Manage CloudWatch log group |

---

## Directory Structure

```
terraform/cdr/aws/cloudtrail-single-account/customer/
├── main.tf              # Lambda, IAM, S3 notification resources
├── provider.tf          # AWS provider config (us-west-1)
├── variables.tf         # Input variable definitions
├── lambda.py            # Lambda function source code
├── terraform.tfvars     # Your variable values (create from template below)
└── README.md            # This file
```

---

## Variables Reference

### Required Variables

| Variable | Type | Description |
|---|---|---|
| `username` | `string` (sensitive) | Basic auth username for the AccuKnox CDR / SIEM endpoint |
| `password` | `string` (sensitive) | Basic auth password for the AccuKnox CDR / SIEM endpoint |
| `target_url` | `string` | HTTPS endpoint URL to forward CloudTrail logs to |
| `bucket_name` | `string` | Name of the **existing** S3 bucket receiving CloudTrail logs |
| `bucket_arn` | `string` | ARN of the **existing** S3 bucket (e.g., `arn:aws:s3:::my-bucket`) |

### Optional Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `accuknox_suffix` | `string` | `"accuknox-cloudtrail-collector"` | Prefix for resource naming (Lambda, IAM role, policies) |
| `chunk_size` | `string` | `""` (3 MB in Lambda) | Max payload size in bytes before sending a chunk. Leave empty for default |
| `line_limit` | `string` | `""` (1000 in Lambda) | Max number of log lines per chunk. Leave empty for default |
| `insecure_tls` | `string` | `""` (false in Lambda) | Skip TLS verification: `"true"` or `"false"`. Leave empty for default |

---

## Step-by-Step Setup

### Step 1: Clone & Navigate

```bash
git clone <your-repo-url>
cd terraform/cdr/aws/cloudtrail-single-account/customer/
```

### Step 2: Authenticate with AWS

```bash
# Option 1: Named profile
export AWS_PROFILE=your-profile

# Option 2: Direct credentials
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=us-west-1
```

Verify authentication:

```bash
aws sts get-caller-identity
```

### Step 3: Configure Variables

Create your `terraform.tfvars` file:

```bash
cat <<EOF > terraform.tfvars
# AccuKnox CDR endpoint credentials
username = "your-accuknox-username"
password = "your-accuknox-password"

# Target HTTPS endpoint
target_url = "https://your-accuknox-cdr-endpoint.com/ingest"

# Existing S3 bucket details
bucket_name = "your-cloudtrail-s3-bucket"
bucket_arn  = "arn:aws:s3:::your-cloudtrail-s3-bucket"

# Resource naming (optional)
accuknox_suffix = "accuknox-cloudtrail-collector"
EOF
```

### Step 4: Initialize Terraform

```bash
terraform init
```

This downloads the required providers (`aws`, `random`).

### Step 5: Plan (Review Changes)

```bash
terraform plan -var-file="terraform.tfvars"
```

Review the output carefully. You should see:
- Lambda function being created
- IAM role and policies being created
- S3 bucket notification being configured
- CloudWatch log group being created

### Step 6: Apply

```bash
terraform apply -var-file="terraform.tfvars"
```

Type `yes` when prompted to confirm. This typically takes **1–3 minutes**.

### Step 7: Verify

After successful apply:

```bash
terraform output
```

Then verify the Lambda is receiving events:

```bash
# Check recent CloudWatch logs for the Lambda
aws logs tail "/aws/lambda/accuknox-cloudtrail-collector-log-forwarder-<suffix>" --follow
```

You should see log entries like:
```
Loaded 150 records from CloudTrail/AWSLogs/123456789012/...
Successfully posted 524288 bytes. Status: 200
```

---

## Lambda Function Behavior

The Lambda function (`lambda.py`) does the following:

1. **Receives S3 event** — triggered by new objects in the CloudTrail S3 bucket
2. **Downloads & decompresses** — reads the gzip-compressed CloudTrail JSON log
3. **Parses records** — extracts the `Records` array from the CloudTrail log
4. **Chunks the data** — splits records into chunks based on:
   - `CHUNK_SIZE_LIMIT` (default: 3 MB)
   - `LINE_LIMIT` (default: 1000 lines)
5. **Forwards via HTTPS** — POSTs each chunk to `TARGET_URL` with:
   - `Content-Type: application/x-ndjson`
   - `Authorization: Basic <base64-encoded-credentials>` (if username/password provided)
6. **Logs results** — success/failure logged to CloudWatch

### Environment Variables

| Env Var | Source | Description |
|---|---|---|
| `TARGET_URL` | `target_url` | HTTPS endpoint for log forwarding |
| `BASIC_USER` | `username` | Basic auth username |
| `BASIC_PASS` | `password` | Basic auth password |
| `INSECURE_TLS_SKIP` | `insecure_tls` | Skip TLS verification (`"true"` / `"false"`) |

> Note: `CHUNK_SIZE_LIMIT` and `LINE_LIMIT` are **not** set as environment variables when `chunk_size` / `line_limit` are empty strings. The Lambda code falls back to its built-in defaults (3 MB and 1000 lines).

---

## Outputs

| Output | Description |
|---|---|
| `lambda_function_name` | Name of the deployed Lambda function |
| `lambda_role_arn` | ARN of the Lambda execution role |

---

## Cleanup / Destroy

To tear down all resources created by this module:

```bash
terraform destroy -var-file="terraform.tfvars"
```

Type `yes` when prompted. This will remove:
- The Lambda function
- The IAM role and policies
- The S3 bucket notification (your bucket and CloudTrail trail remain untouched)
- The CloudWatch log group

> ⚠️ This does **not** delete your S3 bucket or CloudTrail trail — those are existing resources managed outside this module.

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| **`AccessDenied` on S3 bucket** | Ensure `bucket_arn` is correct and the Lambda IAM role has `s3:GetObject` on `arn:aws:s3:::your-bucket/*` |
| **Lambda not triggering** | Verify the S3 bucket has CloudTrail logging enabled and objects are being created. Check `aws s3 ls s3://your-bucket/CloudTrail/` |
| **`AccessDenied` creating IAM role** | Your runner needs `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy` permissions |
| **Target endpoint rejects requests** | Verify `target_url` is correct, `username`/`password` are valid, and the endpoint accepts `application/x-ndjson` POST requests |
| **TLS certificate errors** | If using self-signed certs, set `insecure_tls = "true"` (not recommended for production) |
| **Lambda timeout** | Default timeout is 30s. For very large CloudTrail files, consider increasing `chunk_size` to send smaller batches |
| **Empty `chunk_size` / `line_limit`** | Leaving these as `""` uses Lambda code defaults (3 MB / 1000 lines). To override, set numeric string values like `"1048576"` |

### Useful Debug Commands

```bash
# Check Lambda exists and its config
aws lambda get-function --function-name accuknox-cloudtrail-collector-log-forwarder-<suffix>

# Check S3 bucket notification config
aws s3api get-bucket-notification-configuration --bucket your-cloudtrail-s3-bucket

# Tail Lambda logs in real-time
aws logs tail "/aws/lambda/accuknox-cloudtrail-collector-log-forwarder-<suffix>" --follow

# Manually test: upload a CloudTrail log to trigger Lambda
aws s3 cp test-cloudtrail-log.json.gz s3://your-cloudtrail-s3-bucket/CloudTrail/test/
```

---

## Full vs Customer Variant

| Feature | [Full](../full/) | Customer |
|---|---|---|
| Creates S3 bucket | ✅ Yes | ❌ No (uses existing) |
| Creates CloudTrail trail | ✅ Yes | ❌ No (uses existing) |
| Creates Lambda forwarder | ✅ Yes | ✅ Yes |
| S3 event notification | ✅ Yes | ✅ Yes |
| IAM roles & policies | ✅ Yes | ✅ Yes |
| **Use when** | You need everything from scratch | You already have CloudTrail → S3 set up |

---

## Notes

- The provider defaults to **us-west-1**. Update `provider.tf` if your resources are in a different region.
- The Lambda uses **Python 3.9** runtime. Ensure this is available in your region.
- CloudWatch log retention is set to **3 days** to minimize costs.
- Resource names include a **random 5-character suffix** to avoid naming collisions.
- The `accuknox_suffix` variable controls the prefix for all resource names.
