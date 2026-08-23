# AWS CloudWatch Logs CDR Integration — Customer Variant

This Terraform module deploys a **CloudWatch Logs-to-SIEM forwarding pipeline** for a single AWS account. A Lambda function subscribes to one or more existing CloudWatch Log Groups, receives log events in near real-time via a subscription filter, batches/chunks them, and forwards them to an **AccuKnox CDR / SIEM** endpoint over HTTPS.

Unlike the CloudTrail-based integrations (which forward audit/API-call logs delivered to S3), this module streams **any CloudWatch Log Group** — application logs, Lambda logs, EKS/container logs, VPC Flow Logs (if sent to CloudWatch), etc. — directly via a **subscription filter**, with no S3 bucket in the path.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              AWS Account (us-west-1)                       │
│                                                                            │
│  ┌──────────────────┐     ┌──────────────────┐     ┌────────────────────┐ │
│  │  CloudWatch       │────▶│  Subscription     │────▶│  Lambda Function   │ │
│  │  Log Group(s)     │     │  Filter            │     │  (log_shipper)     │ │
│  │  (existing)       │     │  (real-time push)  │     │                    │ │
│  └──────────────────┘     └──────────────────┘     └─────────┬──────────┘ │
│                                                                │            │
└────────────────────────────────────────────────────────────────┼────────────┘
                                                                 │
                                                                 ▼ HTTPS POST
                                                       ┌─────────────────────┐
                                                       │   AccuKnox CDR /     │
                                                       │      SIEM            │
                                                       └─────────────────────┘
```

### How Data Flows

1. A **CloudWatch Logs Subscription Filter** is attached to each log group you specify in `log_groups`.
2. Whenever a new log event is written to that log group, CloudWatch **invokes the Lambda function** directly (push-based, near real-time — no polling).
3. The Lambda function:
   - Decodes and decompresses the CloudWatch Logs event payload (base64 + gzip)
   - Batches log entries into chunks (bounded by size and line count)
   - POSTs each chunk to `TARGET_URL` with HTTP Basic Auth
4. AccuKnox CDR ingests the forwarded log data.

---

## What This Module Creates

This module has two layers: a **root module** (`terraform/cdr/aws/cloudwatch-customer/`) that wraps a **child module** (`accuknox-exporter/`).

| Resource | Location | Description |
|---|---|---|
| **Lambda Function** (`log_shipper`) | child module | Python 3.11 function that decodes, chunks, and forwards CloudWatch log events |
| **Lambda IAM Role** (`lambda_exec`) | child module | Execution role for the Lambda |
| **IAM Role Policy Attachment** | child module | Attaches AWS-managed `AWSLambdaBasicExecutionRole` (CloudWatch Logs write access) |
| **Lambda Permission** | child module | Allows `logs.amazonaws.com` to invoke the Lambda |
| **CloudWatch Log Subscription Filter(s)** | child module | One per log group in `log_groups` — streams events to the Lambda |

The root module (`main.tf`) is a thin wrapper that instantiates the `accuknox-exporter` child module with a fixed AWS provider alias (`us_west_1`), passing through all variables.

---

## Prerequisites

### 1. Existing Resources (Customer-Owned)

This module assumes you **already have**:

| Resource | Details |
|---|---|
| **CloudWatch Log Group(s)** | The log groups you want to forward (e.g., Lambda logs, application logs, EKS logs) |

> ⚠️ This module does **not** create CloudWatch Log Groups. You must reference existing ones via the `log_groups` variable.

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
| [Terraform](https://www.terraform.io/downloads) | > 5.0 (AWS provider) | `brew install terraform` (macOS) |
| [AWS CLI](https://aws.amazon.com/cli/) | Latest | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |

### 4. AWS Permissions

The IAM user/role running Terraform needs:

| Permission | Purpose |
|---|---|
| `lambda:CreateFunction`, `lambda:UpdateFunctionCode`, `lambda:UpdateFunctionConfiguration`, `lambda:DeleteFunction`, `lambda:GetFunction` | Manage the Lambda function |
| `lambda:AddPermission`, `lambda:RemovePermission` | Allow CloudWatch Logs to invoke the Lambda |
| `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`, `iam:GetRole` | Create and manage the Lambda execution role |
| `logs:PutSubscriptionFilter`, `logs:DeleteSubscriptionFilter`, `logs:DescribeSubscriptionFilters` | Configure log group subscription filters |
| `logs:DescribeLogGroups` | Validate target log groups exist |

---

## Directory Structure

```
terraform/cdr/aws/cloudwatch-customer/
├── main.tf                        # Root module — wraps accuknox-exporter with us-west-1 provider
├── provider.tf                    # AWS provider config (us-west-1, aliased)
├── variables.tf                   # Root-level input variable definitions
├── terraform.tfvars.example       # Example variable values
├── README.md                      # This file
└── accuknox-exporter/             # Child module
    ├── main.tf                    # Lambda, IAM, subscription filter resources
    ├── variables.tf                # Child module variable definitions
    └── lambda_function.py         # Lambda function source code
```

---

## Variables Reference

### Required Variables

| Variable | Type | Description |
|---|---|---|
| `username` | `string` (sensitive) | Basic auth username for the AccuKnox CDR / SIEM endpoint |
| `password` | `string` (sensitive) | Basic auth password for the AccuKnox CDR / SIEM endpoint |
| `cloudwatch_target_url` | `string` | HTTPS endpoint URL to forward CloudWatch log events to |
| `log_groups` | `map(string)` | Map of **existing** CloudWatch Log Group name → friendly source label to subscribe. The label is forwarded to SIEM on every event as `log_source`. **Note:** default is `{}` (empty map) — if left empty, no subscription filters are created and no logs will be forwarded |

### Optional Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `accuknox_suffix` | `string` | `"accuknox_cloudtrail_collector"` | Prefix for resource naming (Lambda function, IAM role) |
| `chunk_size` | `string` | `"3145728"` (3 MB) | Max payload size in bytes before sending a batch |
| `line_limit` | `string` | `"1000"` | Max number of log lines per batch |
| `insecure_tls` | `string` | `"false"` | Skip TLS verification: `"true"` or `"false"` |

---

## Step-by-Step Setup

### Step 1: Clone & Navigate

```bash
git clone <your-repo-url>
cd terraform/cdr/aws/cloudwatch-customer/
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

### Step 3: Identify Target Log Groups

List the CloudWatch Log Groups you want to forward:

```bash
aws logs describe-log-groups --query "logGroups[].logGroupName" --output table
```

Note the exact names — you'll need them for `log_groups`.

> ⚠️ Each CloudWatch Log Group can only have **one** subscription filter destination per filter name. If a log group already has a subscription filter (e.g., feeding another tool), you may need to remove it first or use a different filter name.

### Step 4: Configure Variables

Copy the example variables file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars`:

```hcl
# AccuKnox CDR endpoint credentials
username = "your-accuknox-username"
password = "your-accuknox-password"

# Target HTTPS endpoint
cloudwatch_target_url = "https://your-accuknox-cdr-endpoint.com/ingest"

# Log groups to forward, mapped to a friendly source label
# (the label is sent to SIEM as "log_source" on every event)
log_groups = {
  "/aws/lambda/my-function"     = "My Function"
  "/aws/eks/my-cluster/cluster" = "EKS Cluster"
}

# Resource naming (optional)
accuknox_suffix = "accuknox_cloudtrail_collector"
```

### Step 5: Initialize Terraform

```bash
terraform init
```

This downloads the required providers (`aws` > 5.0, `random` > 3.0).

### Step 6: Plan (Review Changes)

```bash
terraform plan -var-file="terraform.tfvars"
```

Review the output. You should see:
- Lambda function being created
- IAM role and policy attachment being created
- Lambda permission (allow CloudWatch Logs to invoke) being created
- One CloudWatch Log Subscription Filter per entry in `log_groups`

### Step 7: Apply

```bash
terraform apply -var-file="terraform.tfvars"
```

Type `yes` when prompted to confirm. This typically takes **30–90 seconds**.

### Step 8: Verify

After successful apply, check the Lambda is receiving and forwarding events:

```bash
# Tail the Lambda's CloudWatch Logs
aws logs tail "/aws/lambda/accuknox_cloudtrail_collector_cloudwatch_to_https_shipper" --follow
```

Trigger some activity in one of your subscribed log groups (e.g., invoke a Lambda function that logs, or wait for natural application traffic), then confirm you see forwarding activity in the shipper Lambda's logs.

Also verify the subscription filters exist:

```bash
aws logs describe-subscription-filters --log-group-name "/aws/lambda/my-function"
```

---

## Lambda Function Behavior

The Lambda function (`accuknox-exporter/lambda_function.py`) does the following:

1. **Receives CloudWatch Logs event** — triggered directly by the subscription filter (push-based)
2. **Decodes the payload** — CloudWatch Logs events are base64-encoded and gzip-compressed
3. **Parses log events** — extracts the `logGroup` name and `logEvents` array from the decompressed payload
4. **Tags each event** — adds `log_group` (raw CloudWatch log group name) and `log_source` (the friendly label from `log_groups`, falling back to the raw name if unmapped) to every event before forwarding
5. **Batches the data** — groups log entries into chunks based on:
   - `CHUNK_SIZE_LIMIT` (default: 3 MB)
   - `LINE_LIMIT` (default: 1000 lines)
6. **Forwards via HTTPS** — POSTs each batch as JSON to `TARGET_URL` with:
   - `Content-Type: application/json`
   - `Authorization: Basic <base64-encoded-credentials>` (if username/password provided)
   - TLS verification enabled by default (disable via `INSECURE_TLS_SKIP`)

### Environment Variables

| Env Var | Source | Description |
|---|---|---|
| `TARGET_URL` | `cloudwatch_target_url` | HTTPS endpoint for log forwarding |
| `BASIC_USER` | `username` | Basic auth username |
| `BASIC_PASS` | `password` | Basic auth password |
| `CHUNK_SIZE_LIMIT` | `chunk_size` | Max bytes per batch |
| `LINE_LIMIT` | `line_limit` | Max log lines per batch |
| `INSECURE_TLS_SKIP` | `insecure_tls` | Skip TLS verification (`"true"` / `"false"`) |
| `LOG_GROUP_LABELS` | `jsonencode(log_groups)` | JSON map of log group name → friendly label, used to tag each forwarded event with `log_group` and `log_source` |

---

## Adding or Removing Log Groups Later

To add or remove log groups after the initial deployment, simply update the `log_groups` map in `terraform.tfvars` and re-apply:

```hcl
log_groups = {
  "/aws/lambda/my-function"     = "My Function"
  "/aws/eks/my-cluster/cluster" = "EKS Cluster"
  "/aws/lambda/new-function"    = "New Function"  # newly added
}
```

```bash
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

Terraform will diff the `for_each` set on `aws_cloudwatch_log_subscription_filter` and create/destroy only the changed subscription filters — the Lambda function itself is untouched.

---

## Cleanup / Destroy

To tear down all resources created by this module:

```bash
terraform destroy -var-file="terraform.tfvars"
```

Type `yes` when prompted. This will remove:
- All CloudWatch Log Subscription Filters
- The Lambda function
- The Lambda execution IAM role and policy attachment
- The Lambda invoke permission

> ⚠️ This does **not** delete your CloudWatch Log Groups — those are existing resources managed outside this module.

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| **`ResourceAlreadyExistsException` on subscription filter** | The log group already has a subscription filter with a conflicting name/destination. Each log group supports only 1–2 subscription filters (varies by region/quota); remove the conflicting one first |
| **No logs arriving at AccuKnox** | Verify `log_groups` names are exact matches (case-sensitive), check Lambda's own CloudWatch Logs for errors, and confirm `cloudwatch_target_url` is reachable from AWS |
| **`AccessDenied` invoking Lambda from CloudWatch Logs** | Ensure the `aws_lambda_permission.allow_cloudwatch` resource applied successfully; check `principal = "logs.amazonaws.com"` and `source_arn` |
| **Lambda timeout (30s)** | High-volume log groups may exceed the default timeout. Consider increasing `chunk_size`/reducing `line_limit`, or raising the Lambda timeout in `accuknox-exporter/main.tf` |
| **Target endpoint rejects requests** | Verify `cloudwatch_target_url` is correct, `username`/`password` are valid, and the endpoint accepts `application/json` POST requests |
| **TLS certificate errors** | If using self-signed certs, set `insecure_tls = "true"` (not recommended for production) |
| **`log_groups` left empty** | The variable defaults to `[]`. If you forget to populate it, Terraform applies successfully but **no logs are ever forwarded** — always double-check this list |
| **Infinite log loop** | If the Lambda's own execution logs are in a log group that is *also* subscribed, you can create a feedback loop. Avoid subscribing the Lambda's own `/aws/lambda/accuknox_cloudtrail_collector_cloudwatch_to_https_shipper` log group |

### Useful Debug Commands

```bash
# Check Lambda exists and its config
aws lambda get-function --function-name accuknox_cloudtrail_collector_cloudwatch_to_https_shipper

# List all subscription filters on a log group
aws logs describe-subscription-filters --log-group-name "/aws/lambda/my-function"

# Tail Lambda logs in real-time
aws logs tail "/aws/lambda/accuknox_cloudtrail_collector_cloudwatch_to_https_shipper" --follow

# Check Lambda invocation errors/metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=accuknox_cloudtrail_collector_cloudwatch_to_https_shipper \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 300 \
  --statistics Sum

# Manually invoke the Lambda with a test CloudWatch Logs event
aws lambda invoke --function-name accuknox_cloudtrail_collector_cloudwatch_to_https_shipper \
  --payload file://test-event.json out.json
```

---

## CloudWatch Logs vs CloudTrail Integrations

| Feature | CloudWatch (this module) | [CloudTrail Single-Account](../cloudtrail-single-account/) |
|---|---|---|
| Source | Any CloudWatch Log Group | CloudTrail logs delivered to S3 |
| Trigger mechanism | Subscription filter (real-time push) | S3 `ObjectCreated` event |
| Latency | Near real-time (seconds) | Depends on CloudTrail delivery interval (~5 min batches) |
| Data types | Application logs, Lambda logs, EKS logs, custom logs | AWS API/audit activity only |
| Existing resources needed | CloudWatch Log Group(s) | S3 bucket + CloudTrail trail |
| **Use when** | You want to forward application/service logs already in CloudWatch | You want to forward AWS API audit activity |

---

## Notes

- The provider is pinned to **us-west-1** via a provider alias (`aws.us_west_1`) in `provider.tf`. Update if your log groups are in a different region — **the Lambda and log groups must be in the same region** for CloudWatch Logs subscription filters to work.
- The Lambda uses **Python 3.11** runtime with a **30-second timeout**.
- Each log group in `log_groups` gets its own `aws_cloudwatch_log_subscription_filter` resource, all sharing the same filter `name` (derived from `accuknox_suffix`) and the same destination Lambda.
- The subscription filter uses an empty `filter_pattern` (`""`), meaning **all** log events in the subscribed log groups are forwarded — there's no server-side filtering by content.
- Lambda execution logs (its own logs) are managed by the AWS-managed `AWSLambdaBasicExecutionRole` policy and go to the AWS-default `/aws/lambda/<function-name>` log group.
- A random 2-byte hex ID (`random_id.server_prefix`) is appended to the Lambda zip filename to avoid archive caching issues between deployments — it does not affect the function name.

---

## Log Group Change

**Core insight:** the raw CloudWatch payload delivered to the Lambda already contains the source log group's name (`logGroup` field), it just was never included in the JSON forwarded to SIEM. So the fix did not require plumbing new information into the Lambda — it required (1) attaching a human-readable label to each log group and (2) having the Lambda read the log group name it already receives, look up the label, and stamp both onto every event before forwarding.

### What changed

**`log_groups` variable — type change**
- Old: `list(string)` — a flat list of log group names, e.g. `["yubi-networkFW", "yubi-vpc-logs-test"]`
- New: `map(string)` — log group name → friendly label, e.g. `{ "yubi-networkFW" = "Network Firewall" }`
- Changed in: `variables.tf` (root module) and `accuknox-exporter/variables.tf` (child module)

**`accuknox-exporter/main.tf`**
- `aws_cloudwatch_log_subscription_filter.logging_filter`: `for_each` changed from `toset(var.log_groups)` to `var.log_groups` (iterating the map directly), and `log_group_name` changed from `each.value` to `each.key`
- Added a new Lambda environment variable, `LOG_GROUP_LABELS = jsonencode(var.log_groups)`, so the label map is available to the Lambda at runtime

**`accuknox-exporter/lambda_function.py`**
- `get_env_config()` now also reads `LOG_GROUP_LABELS` and parses it from JSON into a dict
- `lambda_handler()` now reads `log_data['logGroup']` (the log group name, already present in the decoded CloudWatch payload) and looks up its label from the parsed `LOG_GROUP_LABELS` map, falling back to the raw log group name if it isn't in the map
- Each event is now enriched with two new fields, `log_group` and `log_source`, before being serialized and sent to SIEM

**`terraform.tfvars`** *(gitignored, not tracked in git)*
- Converted the existing list to the new map format, keeping the same three log groups and adding a descriptive label for each: `yubi-networkFW` → `Network Firewall`, `yubi-vpc-logs-test` → `VPC Flow Logs`, `yubi-waf-logs` → `WAF Logs`

**`terraform.tfvars.example`**
- Updated to show the new map format with example labels

**`README.md`**
- Updated the `log_groups` row in the Variables Reference table, the Step 4 example, the "Adding or Removing Log Groups Later" example, and the Lambda Function Behavior section (steps + environment variable table) to reflect the map format and the new enrichment behavior — this section was added to record why and how

### Result

Every event sent to SIEM now carries two extra fields identifying its source:

```json
{
  "message": "2 735362266271 eni-03c6199f55722a5c9 - - - - - - - 1787223257 1787223286 - NODATA",
  "@timestamp": "2026-08-20T10:55:05.668851481Z",
  "user_agent": { "original": "Python-urllib/3.11" },
  "id": "39856410467245011907415658791415407293609821851029405696",
  "timestamp": 1787223257000,
  "log_group": "yubi-networkFW",
  "log_source": "Network Firewall"
}
```

- `log_group` — the raw CloudWatch log group name (always present, exact match to what's configured in `log_groups`)
- `log_source` — the friendly label configured for that log group; if a log group is ever left without a label in `log_groups` (e.g. mapped to an empty string) or a new one is added later without being redeployed, `log_source` falls back to the raw log group name rather than being blank

### Things to be aware of before applying

- This is a breaking change to the `log_groups` variable's shape — `terraform.tfvars` **must** be updated to the map format before running `terraform plan`/`apply`, or Terraform will error on a type mismatch.
- Because the `for_each` key type changes (from a set to a map), Terraform will show the existing `aws_cloudwatch_log_subscription_filter` resources as destroyed and recreated on the next apply. The Lambda function itself is not replaced, so there should be no gap in the Lambda being able to receive/forward logs — only a brief moment while each subscription filter is recreated.
- No new AWS permissions or resources are required — this only changes variable shape, one Lambda environment variable, and the Lambda's own code.
