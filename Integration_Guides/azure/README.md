# Azure Activity Logs CDR — Event Hub Pipeline

This Terraform module deploys an **Azure Event Hub pipeline** that captures subscription-level activity logs (Administrative, Security, ServiceHealth, Alert, Recommendation, Policy, Autoscale, ResourceHealth) and makes them available to external CDR/SIEM tools such as **AccuKnox CDR** via the Event Hub.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                                │
│                                                                          │
│  ┌──────────────────────────────────────────────────┐                   │
│  │         Azure Monitor Diagnostic Settings         │                   │
│  │   (captures 8 activity log categories)            │                   │
│  └──────────────────────┬───────────────────────────┘                   │
│                         │                                                │
│                         ▼                                                │
│  ┌──────────────────────────────────────────────────┐                   │
│  │              Event Hub Namespace                  │                   │
│  │         (Basic / Standard / Premium)              │                   │
│  │  ┌────────────────────────────────────────────┐  │                   │
│  │  │             Event Hub                       │  │                   │
│  │  │         (partitioned message store)         │  │                   │
│  │  └────────────────────────────────────────────┘  │                   │
│  │                                                  │                   │
│  │  ┌──────────────┐  ┌──────────────┐             │                   │
│  │  │  Listen Rule  │  │  Send Rule    │             │                   │
│  │  │ (logstash)    │  │ (ak-sender)   │             │                   │
│  │  └──────┬───────┘  └──────────────┘             │                   │
│  └─────────┼────────────────────────────────────────┘                   │
└────────────┼────────────────────────────────────────────────────────────┘
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
| **Resource Group** | Container for all Azure resources |
| **Event Hub Namespace** | Messaging backbone (Basic/Standard/Premium tier) |
| **Event Hub** | Partitioned message store within the namespace |
| **Diagnostic Setting** | Routes 8 activity log categories from the subscription to the Event Hub |
| **Authorization Rule (listen)** | Listen-only rule for CDR/SIEM consumer (logstash) |
| **Authorization Rule (send)** | Send-only rule for AccuKnox sender (ak-sender) |
| **Namespace Authorization Rule** | Send rule at namespace level for activity log ingestion |

---

## Activity Log Categories Captured

| Category | Description |
|---|---|
| **Administrative** | Create, update, delete, action operations on resources |
| **Security** | Security alerts and recommendations |
| **ServiceHealth** | Azure service incident and maintenance advisories |
| **Alert** | Metric alert state changes |
| **Recommendation** | Azure Advisor recommendations |
| **Policy** | Azure Policy audit results |
| **Autoscale** | Autoscale engine operations |
| **ResourceHealth** | Resource health availability changes |

---

## Prerequisites

### 1. Azure Account & Permissions

You need an Azure account with permissions to:

| Permission | Purpose |
|---|---|
| `Microsoft.Resources/subscriptions/resourceGroups/write` | Create resource group |
| `Microsoft.EventHub/namespaces/write` | Create Event Hub namespace |
| `Microsoft.EventHub/namespaces/eventhubs/write` | Create Event Hub |
| `Microsoft.Insights/diagnosticSettings/write` | Configure diagnostic settings |
| `Microsoft.Authorization/roleAssignments/write` | (if needed for RBAC) |

An **Owner** or **Contributor** role on the subscription is typically sufficient.

### 2. Azure CLI Authentication

```bash
az login
az account set --subscription "your-subscription-id"
```

### 3. Tools Required

| Tool | Minimum Version | Installation |
|---|---|---|
| [Terraform](https://www.terraform.io/downloads) | ~> 1.12 | `brew install terraform` (macOS) |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | Latest | [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |

---

## Directory Structure

```
terraform/cdr/azure/
├── main.tf              # Core resources: resource group, Event Hub, diagnostic settings
├── locals.tf            # Local values for naming conventions
├── provider.tf          # Azure provider config and version constraints
├── variables.tf         # Input variable definitions
├── output.tf            # Output values
├── terraform.tfvars.example  # Example variable values
└── README.md            # This file
```

---

## Variables Reference

### Required Variables

| Variable | Type | Description |
|---|---|---|
| `subscription_id` | `string` (sensitive) | Azure subscription ID where resources will be created |

### Optional Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | `"East US"` | Azure region for resource deployment |
| `resource_group_name` | `string` | `"accuknox-cdr"` | Name of the resource group |
| `event_hub_namespace_prefix` | `string` | `"accuknox-cdr"` | Prefix for Event Hub namespace (suffix is auto-generated) |
| `event_hub_namespace_sku` | `string` | `"Basic"` | Event Hub tier: `Basic`, `Standard`, or `Premium` |
| `event_hub_namespace_capacity` | `number` | `1` | Throughput units (1 TU = 1 MB/s ingress, 2 MB/s egress) |
| `event_hub_namespace_autoinflate` | `bool` | `false` | Enable auto-inflate for automatic scaling |
| `event_hub_prefix` | `string` | `"default"` | Prefix for Event Hub name (suffix is auto-generated) |
| `event_hub_partition_count` | `number` | `1` | Number of partitions (1-32) |
| `event_hub_message_retention` | `number` | `1` | Message retention in days (1-7 for Basic, up to 90 for Premium) |
| `authorization_rule_name_prefix` | `string` | `"logstash"` | Prefix for authorization rule names (suffix is auto-generated) |

### Naming Convention

All resource names use the pattern: `{prefix}-{random4}` where `{random4}` is a 4-character lowercase alphanumeric string. This avoids naming collisions across deployments.

| Resource | Name Pattern |
|---|---|
| Event Hub Namespace | `{event_hub_namespace_prefix}-{random}` → `accuknox-cdr-ab12` |
| Event Hub | `{event_hub_prefix}-{random}` → `default-ab12` |
| Authorization Rules | `{authorization_rule_name_prefix}-{random}-listen`, `-ak-sender`, `-activity_logs` |

---

## Step-by-Step Setup

### Step 1: Clone and Navigate

```bash
git clone <your-repo-url>
cd terraform/cdr/azure/
```

### Step 2: Authenticate with Azure

```bash
# Login to Azure
az login

# Set the target subscription
az account set --subscription "your-subscription-id"

# Verify
az account show
```

### Step 3: Configure Variables

Copy the example variables file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` and update the required value:

```hcl
# Required: your Azure subscription ID
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

All other variables have sensible defaults. Adjust the optional values only if needed.

### Step 4: Initialize Terraform

```bash
terraform init
```

This downloads the required providers (`azurerm` v4.32.0, `random` v3.7.2).

### Step 5: Plan (Review Changes)

```bash
terraform plan -var-file="terraform.tfvars"
```

Review the output. You should see:
- Resource group being created
- Event Hub namespace being created
- Event Hub being created
- Authorization rules being created
- Diagnostic setting being created (routes activity logs to Event Hub)

### Step 6: Apply

```bash
terraform apply -var-file="terraform.tfvars"
```

Type `yes` when prompted to confirm. This typically takes **2-5 minutes**.

### Step 7: Verify

After successful apply:

```bash
terraform output
```

Then verify the Event Hub is receiving activity logs:

```bash
# List Event Hubs in the namespace
az eventhub eventhub list --namespace-name <namespace-name> --resource-group <resource-group-name>

# Check diagnostic settings
az monitor diagnostic-settings list --resource "/subscriptions/<subscription-id>"
```

---

## Outputs

| Output | Description | Sensitive |
|---|---|---|
| `event_hub_primary_connection_string` | Primary connection string (listen-only) for CDR/SIEM consumer | Yes |
| `event_hub_secondary_connection_string` | Secondary connection string (listen-only) for CDR/SIEM consumer | Yes |
| `ak-sender` | Authorization rule ID for the AccuKnox sender | No |
| `logstash` | Authorization rule ID for the logstash/CDR listener | No |
| `even_hub_name` | Name of the created Event Hub | No |

---

## Integration with AccuKnox CDR

After running this module:

1. Note the `event_hub_primary_connection_string` from the Terraform output (sensitive — use `terraform output -raw event_hub_primary_connection_string`)
2. In the AccuKnox CDR dashboard, configure a new Azure Event Hub data source
3. Provide the connection string and Event Hub name
4. AccuKnox CDR will begin consuming activity log messages from the Event Hub

```bash
# Get the connection string for CDR setup
terraform output -raw event_hub_primary_connection_string
```

---

## Authorization Rules Explained

This module creates **three** authorization rules:

| Rule | Permissions | Purpose |
|---|---|---|
| `{prefix}-listen` | Listen only | Used by CDR/SIEM consumer to read messages |
| `{prefix}-ak-sender` | Send only | Used by AccuKnox to send test/control messages |
| `{prefix}-activity_logs` | Send only | Used by Azure Monitor to ingest activity logs into the Event Hub |

---

## Cleanup / Destroy

To tear down all resources created by this module:

```bash
terraform destroy -var-file="terraform.tfvars"
```

Type `yes` when prompted. This will remove:
- The diagnostic setting
- The authorization rules
- The Event Hub
- The Event Hub namespace
- The resource group and all contained resources

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| **`AuthorizationFailed`** | Ensure you have `Contributor` or `Owner` role on the subscription |
| **`InvalidSubscriptionId`** | Verify `subscription_id` is a valid GUID format (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) |
| **Namespace name already taken** | The random suffix should prevent this, but try a different `event_hub_namespace_prefix` |
| **No activity logs appearing** | Diagnostic settings may take 5-10 minutes to start flowing. Verify with `az monitor diagnostic-settings list` |
| **Throttling / throughput exceeded** | Increase `event_hub_namespace_capacity` or enable `event_hub_namespace_autoinflate` |
| **Provider version mismatch** | This module requires Terraform ~> 1.12 and azurerm 4.32.0. Check with `terraform version` |
| **Region not available** | Some SKUs (Premium) are not available in all regions. Try a different `location` or SKU |

### Useful Debug Commands

```bash
# Check Event Hub namespace
az eventhub namespace show --name <namespace> --resource-group <rg>

# List Event Hubs
az eventhub eventhub list --namespace-name <namespace> --resource-group <rg>

# Check diagnostic settings
az monitor diagnostic-settings show --name <name> --resource "/subscriptions/<sub-id>"

# Test Event Hub connectivity (using Azure CLI)
az eventhub eventhub authorization-rule keys list \
  --namespace-name <namespace> \
  --eventhub-name <eventhub> \
  --name <rule-name> \
  --resource-group <rg>
```

---

## Event Hub SKU Comparison

| Feature | Basic | Standard | Premium |
|---|---|---|---|
| Price (per TU) | Lowest | Medium | Highest |
| Max Throughput Units | 1 | 20 | 1 |
| Auto-inflate | No | Yes | Yes |
| Partition Count | Up to 32 | Up to 32 | Up to 1024 |
| Message Retention | 1 day | 1-7 days | Up to 90 days |
| Capture | No | Yes | Yes |
| Geo-Disaster Recovery | No | Yes | Yes |

> **Recommendation:** Start with **Basic** for most CDR use cases. Upgrade to **Standard** if you need auto-scaling, longer retention, or higher throughput.

---

## Notes

- This module uses the **azurerm** provider v4.32.0 with **Terraform ~> 1.12**
- Resource names include a **random 4-character suffix** to avoid naming collisions
- The diagnostic setting captures **8 activity log categories** at the subscription level
- The Event Hub namespace is configured with **public network access enabled** by default
- Connection strings are marked as **sensitive** in Terraform outputs
- For production deployments, consider enabling auto-inflate and increasing capacity
