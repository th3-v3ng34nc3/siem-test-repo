# GCP Audit Log Exporter via Terraform (CDR — Cloud Detection & Response)

This Terraform module provisions a **GCP Pub/Sub pipeline** that captures organization-level audit logs (e.g., VM deletions, firewall changes, IAM modifications) and makes them available to external CDR/SIEM tools such as **AccuKnox CDR**.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GCP Organization                            │
│                                                                     │
│  ┌──────────────────────────────────────────────────┐              │
│  │          Org-Level Audit Log Sink                 │              │
│  │  (filters logs from specified project IDs)        │              │
│  └──────────────────────┬───────────────────────────┘              │
│                         │                                           │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────┐              │
│  │              Pub/Sub Topic                        │              │
│  │         (accuknox-siem)                           │              │
│  └──────────────────────┬───────────────────────────┘              │
│                         │                                           │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────┐              │
│  │         Pub/Sub Subscription                      │              │
│  │        (accuknox-siem-sub)                        │              │
│  └──────────────────────┬───────────────────────────┘              │
│                         │                                           │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────┐              │
│  │     Service Account (reader)                      │              │
│  │  (roles/pubsub.subscriber)                        │              │
│  └──────────────────────┬───────────────────────────┘              │
│                         │                                           │
└─────────────────────────┼───────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   AccuKnox CDR / SIEM │
              └───────────────────────┘
```

---

## What This Module Creates

| Resource | Description |
|---|---|
| **GCP APIs** | Enables `pubsub.googleapis.com`, `iam.googleapis.com`, `logging.googleapis.com` |
| **Pub/Sub Topic** | Receives audit log messages from the org-level sink |
| **Pub/Sub Subscription** | Consumes messages from the topic (with configurable retention, ack deadline, etc.) |
| **Service Account** | Dedicated reader SA with `roles/pubsub.subscriber` for consuming logs |
| **Organization Log Sink** | Routes audit logs from specified projects to the Pub/Sub topic |
| **IAM Binding** | Grants the log sink's writer identity `roles/pubsub.publisher` on the topic |

---

## Prerequisites

### 1. GCP Account & Permissions

You need a GCP account with **Organization Admin** level permissions (or equivalent) to:
- Create custom IAM roles at the organization level
- Create service accounts
- Create organization-level log sinks
- Bind IAM policies

### 2. Service Account for Terraform

Create a **dedicated Service Account** in your GCP project to run Terraform. This SA needs the following roles:

| IAM Role | Purpose |
|---|---|
| `roles/logging.admin` | Create and manage log sinks |
| `roles/resourcemanager.projectIamAdmin` | Manage project-level IAM bindings |
| `roles/pubsub.admin` | Create topics, subscriptions, and IAM bindings |
| `roles/iam.serviceAccountAdmin` | Create the reader service account |
| `roles/iam.serviceAccountKeyAdmin` | Generate keys for the reader SA (if needed) |
| `roles/serviceusage.serviceUsageAdmin` | Enable required GCP APIs |
| `roles/organization.admin` | Create organization-level log sinks |

Alternatively, use a Service Account with the **Owner** role (`roles/owner`) for full access.

### 3. Required GCP APIs

The following APIs must be enabled on the host project (the module will enable them automatically):

- **Cloud Pub/Sub API** (`pubsub.googleapis.com`)
- **Cloud IAM API** (`iam.googleapis.com`)
- **Cloud Logging API** (`logging.googleapis.com`)

### 4. Tools Required

| Tool | Minimum Version | Installation |
|---|---|---|
| [Terraform](https://www.terraform.io/downloads) | >= 1.1.0 | `brew install terraform` (macOS) |
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | Latest | [Install guide](https://cloud.google.com/sdk/docs/install) |

---

## Directory Structure

```
terraform/cdr/gcp/
├── main.tf              # Core resources: provider, APIs, Pub/Sub, sink, IAM
├── variables.tf         # Input variable definitions
├── outputs.tf           # Output values
├── terraform.tfvars     # Your variable values (create from template below)
└── README.md            # This file
```

---

## Variables Reference

### Required Variables

| Variable | Type | Description |
|---|---|---|
| `project_id` | `string` | The GCP project ID where Pub/Sub resources will be created |
| `projects` | `list(string)` | List of GCP project IDs to include in the audit log sink filter |
| `region` | `string` | GCP region for resource deployment (e.g., `us-central1`) |
| `org_id` | `string` | GCP Organization ID (numeric, e.g., `123456789012`) |

### Optional Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `pubsub_topic_name` | `string` | `"accuknox-siem"` | Name of the Pub/Sub topic |
| `subscription_name` | `string` | `"accuknox-siem-sub"` | Name of the Pub/Sub subscription |
| `ack_deadline_seconds` | `number` | `10` | Max time (seconds) before a message is re-delivered |
| `retain_acked_messages` | `bool` | `false` | Whether to retain acknowledged messages |
| `message_retention_duration` | `string` | `"604800s"` | How long unacknowledged messages are retained (7 days) |
| `enable_message_ordering` | `bool` | `false` | Enable message ordering |
| `expiration_policy_ttl` | `string` | `"2678400s"` | Subscription expiration TTL (31 days) |
| `enable_exactly_once_delivery` | `bool` | `true` | Enable exactly-once delivery semantics |
| `service_account_id` | `string` | `"accuknox-cdr-pubsub-reader"` | ID of the reader service account |
| `sink_name` | `string` | `"accuknox-audit-logs-to-pubsub"` | Name of the organization log sink |

---

## Step-by-Step Setup

### Step 1: Clone & Navigate

```bash
git clone <your-repo-url>
cd terraform/cdr/gcp/
```

### Step 2: Authenticate with GCP

Using a service account key file:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your-service-account-key.json"
```

Or using `gcloud`:

```bash
gcloud auth application-default login
gcloud config set project <your-project-id>
```

### Step 3: Configure Variables

Create your `terraform.tfvars` file (or edit the existing one):

```bash
cp terraform.tfvars.example terraform.tfvars  # if example exists
```

Edit `terraform.tfvars` with your values:

```hcl
# ===========================================
# Required Variables — MUST be filled in
# ===========================================

# The GCP project ID where resources will be created
project_id = "my-gcp-project-123"

# List of GCP project IDs to include in the audit log sink filter
projects = [
  "project-alpha",
  "project-beta",
  "project-gamma",
]

# GCP region for resource deployment
region = "us-central1"

# GCP Organization ID (numeric)
org_id = "123456789012"


# ===========================================
# Optional Variables — defaults are fine
# ===========================================

pubsub_topic_name    = "accuknox-siem"
subscription_name    = "accuknox-siem-sub"
ack_deadline_seconds = 10

retain_acked_messages      = false
message_retention_duration = "604800s"  # 7 days
enable_message_ordering    = false
expiration_policy_ttl      = "2678400s"  # 31 days
enable_exactly_once_delivery = true

service_account_id = "accuknox-cdr-pubsub-reader"
sink_name          = "accuknox-audit-logs-to-pubsub"
```

### Step 4: Initialize Terraform

```bash
terraform init
```

This downloads the required providers (`google`, `google-beta`).

### Step 5: Plan (Review Changes)

```bash
terraform plan -var-file="terraform.tfvars"
```

Review the output carefully. You should see:
- APIs being enabled
- Pub/Sub topic & subscription being created
- Service account being created
- Organization log sink being created
- IAM bindings being applied

### Step 6: Apply

```bash
terraform apply -var-file="terraform.tfvars"
```

Type `yes` when prompted to confirm. This typically takes **2–5 minutes**.

### Step 7: Verify

After successful apply, note the outputs:

```bash
terraform output
```

Expected outputs:

| Output | Description |
|---|---|
| `project_id` | The project ID where resources were created |
| `topic` | Pub/Sub topic name |
| `subscription` | Pub/Sub subscription name |
| `serviceAccount_email` | Email of the reader service account |

Use the `serviceAccount_email` and `topic` to configure your CDR/SIEM consumer.

---

## Outputs

| Output | Description |
|---|---|
| `project_id` | The GCP project ID used for deployment |
| `topic` | Name of the created Pub/Sub topic |
| `subscription` | Name of the created Pub/Sub subscription |
| `serviceAccount_email` | Email of the reader service account (use this for CDR integration) |

---

## How the Log Sink Filter Works

The organization log sink uses a filter to include only audit logs from the specified projects:

```
(resource.labels.project_id="project-alpha" OR resource.labels.project_id="project-beta" OR resource.labels.project_id="project-gamma")
```

This ensures only logs from your target projects are forwarded to the Pub/Sub topic — not the entire organization.

---

## Cleanup / Destroy

To tear down all resources created by this module:

```bash
terraform destroy -var-file="terraform.tfvars"
```

Type `yes` when prompted. This will remove:
- The Pub/Sub topic and subscription
- The reader service account
- The organization log sink
- All IAM bindings
- Enabled APIs (if `disable_on_destroy = true`)

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| **`Error:google_organization` not found** | Verify `org_id` is the correct numeric organization ID, not the domain name |
| **Permission denied creating log sink** | Ensure the runner SA has `roles/logging.admin` and `roles/organization.admin` |
| **API not enabled** | The module auto-enables APIs, but if it fails, run: `gcloud services enable pubsub.googleapis.com iam.googleapis.com logging.googleapis.com` |
| **Subscription expiration** | Default TTL is 31 days. Adjust `expiration_policy_ttl` if the subscription keeps expiring |
| **Messages not arriving** | Verify the `projects` list contains the correct project IDs and that audit logs are enabled in those projects |
| **`GOOGLE_APPLICATION_CREDENTIALS` not set** | Export the env var: `export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"` |

### Useful Debug Commands

```bash
# Check if APIs are enabled
gcloud services list --enabled --filter="name:pubsub OR name:iam OR name:logging"

# List Pub/Sub topics
gcloud pubsub topics list

# List organization log sinks
gcloud logging sinks list --organization=<org-id>

# Check sink logs (last 100 entries)
gcloud logging read "resource.type=pubsub_topic" --limit=100
```

---

## Integration with AccuKnox CDR

After running this module:

1. Note the `serviceAccount_email` from the Terraform output
2. In the AccuKnox CDR dashboard, configure a new GCP data source
3. Provide the **Pub/Sub subscription** name and **service account credentials**
4. AccuKnox CDR will begin consuming audit log messages from the subscription

---

## Notes

- This module creates an **organization-level** log sink, which requires Organization Admin permissions
- The sink is configured with `include_children = true`, so logs from all child projects/folders in the org are included (filtered by the `projects` list)
- The Pub/Sub subscription defaults to **exactly-once delivery** for reliability
- Messages are retained for **7 days** if unacknowledged
- The subscription expires after **31 days** — renew or adjust `expiration_policy_ttl` as needed
