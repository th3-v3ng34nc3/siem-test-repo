# AWS Config Single-Account CDR — Customer Variant

This Terraform module deploys an **AWS Config-to-SIEM log forwarding pipeline** for a single AWS account using an **existing S3 bucket and AWS Config recorder/delivery channel**. A Lambda function is triggered by S3 object creation events, decompresses the AWS Config snapshot/history files, chunks them, and forwards them to an AccuKnox CDR / SIEM endpoint via HTTPS.

AWS Config has no CloudWatch Logs delivery option — S3 is the only place it writes to. This module reacts to file arrival rather than streaming or polling, the same way the [CloudTrail variant](../../cloudtrail-single-account/customer/) does.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           AWS Account                                    │
│                                                                          │
│  ┌──────────────┐     ┌──────────────────┐     ┌─────────────────────┐ │
│  │  AWS Config   │────▶│  S3 Bucket        │────▶│  Lambda Function    │ │
│  │  (existing)   │     │  (existing)       │     │  (config forwarder) │ │
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
| **Lambda Function** | Python function that reads, decompresses, chunks, and forwards AWS Config files |
| **Lambda IAM Role** | Execution role with S3 read + CloudWatch Logs permissions |
| **Lambda IAM Policies** | `s3:GetObject` on the bucket (scoped to the Config key prefix), plus CloudWatch Logs write access |
| **S3 Bucket Notification** | Triggers the Lambda on every matching `s3:ObjectCreated:*` event |
| **Lambda Permission** | Allows S3 to invoke the Lambda function |
| **CloudWatch Log Group** | Stores Lambda execution logs (3-day retention) |

---

## Prerequisites

### 1. Existing Resources (Customer-Owned)

This module assumes you **already have** the following in your AWS account:

| Resource | Details |
|---|---|
| **S3 Bucket** | Receiving AWS Config snapshot/history files (gzip-compressed JSON) |
| **AWS Config Recorder + Delivery Channel** | Enabled and delivering to the above bucket |

> ⚠️ This module does **not** enable AWS Config or create the S3 bucket. If you need those as well, use the [full variant](../full/) instead.

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
Integration_Guides/aws/aws-config/customer/
├── main.tf              # Lambda, IAM, S3 notification resources
├── provider.tf          # AWS provider config (region set via var.region)
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
| `target_url` | `string` | HTTPS endpoint URL to forward AWS Config files to |
| `bucket_name` | `string` | Name of the **existing** S3 bucket receiving AWS Config files |
| `bucket_arn` | `string` | ARN of the **existing** S3 bucket (e.g., `arn:aws:s3:::my-bucket`) |
| `region` | `string` | AWS region the bucket above is actually in. No default on purpose — S3 event notifications can only invoke a Lambda in the same region as the bucket, so a wrong or assumed region breaks the trigger (or the apply itself) rather than just deploying to the "wrong" place |

### Optional Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `accuknox_suffix` | `string` | `"accuknox-awsconfig-collector"` | Prefix for resource naming (Lambda, IAM role, policies) |
| `config_key_prefix` | `string` | `""` | Scopes the S3 trigger to AWS Config's own files, e.g. `AWSLogs/111122223333/Config/`. Needed whenever the bucket also receives CloudTrail or other logs |
| `chunk_size` | `string` | `""` (3 MB in Lambda) | Max payload size in bytes before sending a chunk. Leave empty for default |
| `line_limit` | `string` | `""` (1000 in Lambda) | Max number of configuration items per chunk. Leave empty for default |
| `insecure_tls` | `string` | `""` (false in Lambda) | Skip TLS verification: `"true"` or `"false"`. Leave empty for default |
| `lambda_memory_mb` | `number` | `512` | Lambda memory. AWS Config snapshots (full account inventory) are decompressed entirely in memory and can be much larger than a CloudTrail delta |
| `lambda_timeout_seconds` | `number` | `120` | Lambda timeout, sized up from AWS's 3-second default to give large snapshots room to download, decompress, and post in multiple chunks |

---

## Step-by-Step Setup

### Step 1: Clone & Navigate

```bash
git clone <your-repo-url>
cd Integration_Guides/aws/aws-config/customer/
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
bucket_name = "your-aws-config-s3-bucket"
bucket_arn  = "arn:aws:s3:::your-aws-config-s3-bucket"

# Region the bucket above is actually in (required, no default)
region = "us-west-2"

# Scope the trigger to AWS Config's own files
config_key_prefix = "AWSLogs/123456789012/Config/"

# Resource naming (optional)
accuknox_suffix = "accuknox-awsconfig-collector"
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
aws logs tail "/aws/lambda/accuknox-awsconfig-collector-log-forwarder-<suffix>" --follow
```

You should see log entries like:
```
Loaded 150 configurationItems from AWSLogs/123456789012/Config/us-east-1/2026/8/21/ConfigSnapshot/...
Successfully posted 524288 bytes. Status: 200
```

---

## Lambda Function Behavior

The Lambda function (`lambda.py`) does the following:

1. **Receives S3 event** — triggered by new objects under the AWS Config key prefix
2. **Downloads & decompresses** — reads the gzip-compressed AWS Config JSON log
3. **Parses items** — extracts the `configurationItems` array (present in both ConfigSnapshot and ConfigHistory files)
4. **Chunks the data** — splits items into chunks based on:
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
| `CHUNK_SIZE_LIMIT` | `chunk_size` | Only set when non-empty; otherwise the Lambda's 3 MB default applies |
| `LINE_LIMIT` | `line_limit` | Only set when non-empty; otherwise the Lambda's 1000-item default applies |

> Note: unlike the CloudTrail variant, this Lambda always sets explicit `memory_size`/`timeout` on the function (via `lambda_memory_mb`/`lambda_timeout_seconds`) rather than relying on AWS's defaults (128 MB / 3s) — a full AWS Config snapshot can be a lot larger than a single CloudTrail delta.

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
- The S3 bucket notification (your bucket and AWS Config recorder remain untouched)
- The CloudWatch log group

> ⚠️ This does **not** delete your S3 bucket or AWS Config recorder/delivery channel — those are existing resources managed outside this module.

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| **`AccessDenied` on S3 bucket** | Ensure `bucket_arn` is correct and the Lambda IAM role has `s3:GetObject` on `arn:aws:s3:::your-bucket/*` |
| **Lambda not triggering** | Verify AWS Config is actually delivering to the bucket: `aws s3 ls s3://your-bucket/AWSLogs/<account-id>/Config/ --recursive` |
| **Lambda fires on unrelated files too** | Set `config_key_prefix` — common when the bucket is shared with CloudTrail or other deliveries |
| **`AccessDenied` creating IAM role** | Your runner needs `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy` permissions |
| **Target endpoint rejects requests** | Verify `target_url` is correct, `username`/`password` are valid, and the endpoint accepts `application/x-ndjson` POST requests |
| **TLS certificate errors** | If using self-signed certs, set `insecure_tls = "true"` (not recommended for production) |
| **Lambda timeout on large accounts** | Increase `lambda_timeout_seconds` and/or `lambda_memory_mb` — a full snapshot for a large account can take longer to download, decompress, and post |
| **Empty `chunk_size` / `line_limit`** | Leaving these as `""` uses Lambda code defaults (3 MB / 1000 lines). To override, set numeric string values like `"1048576"` |

### Useful Debug Commands

```bash
# Check Lambda exists and its config
aws lambda get-function --function-name accuknox-awsconfig-collector-log-forwarder-<suffix>

# Check S3 bucket notification config
aws s3api get-bucket-notification-configuration --bucket your-aws-config-s3-bucket

# Tail Lambda logs in real-time
aws logs tail "/aws/lambda/accuknox-awsconfig-collector-log-forwarder-<suffix>" --follow

# Manually test: copy a real AWS Config snapshot object to trigger the Lambda
aws s3 cp existing-config-snapshot.json.gz s3://your-aws-config-s3-bucket/AWSLogs/123456789012/Config/us-east-1/2026/8/21/ConfigSnapshot/test.json.gz
```

---

## Full vs Customer Variant

| Feature | [Full](../full/) | Customer |
|---|---|---|
| Creates S3 bucket | ✅ Yes | ❌ No (uses existing) |
| Enables AWS Config recorder + delivery channel | ✅ Yes | ❌ No (uses existing) |
| Creates Lambda forwarder | ✅ Yes | ✅ Yes |
| S3 event notification | ✅ Yes | ✅ Yes |
| IAM roles & policies | ✅ Yes | ✅ Yes |
| **Use when** | You need everything from scratch | You already have AWS Config → S3 set up |

---

## Notes

- The provider region comes from the required `region` variable — no default, and no need to edit
  `provider.tf` directly. Set it to match `bucket_name`/`bucket_arn`'s actual region.
- The Lambda uses **Python 3.9** runtime, matching the CloudTrail variant.
- CloudWatch log retention is set to **3 days** to minimize costs.
- Resource names include a **random 5-character suffix** to avoid naming collisions.
- The `accuknox_suffix` variable controls the prefix for all resource names.
- This kit knows nothing about AccuKnox's Kubernetes cluster, tenants, or Vault — `target_url`/`username`/`password` are supplied to it already-built, exactly like every other kit in `Integration_Guides/`.
