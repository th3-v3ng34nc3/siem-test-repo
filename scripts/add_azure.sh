#!/bin/bash

set -a
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
COMMON_ENVS="$SCRIPT_DIR/common.sh"
source $COMMON_ENVS

# --- Git Root Detection ---
# ENVS_DIR should be the root of the git, if git not found exit
ENVS_DIR=$(git rev-parse --show-toplevel 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Error: This directory is not part of a Git repository."
    exit 1
fi

echo $ENVS_DIR
vault_check_connect
# Define the base location using the git root
DIR_LOC="$ENVS_DIR/$DIR_PREFIX"
TPL_LOC="$ENVS_DIR/templates"
CLOUDTRAIL_TPL="$TPL_LOC/azure-collector-tpl"

# --- 2. ENV ID Input and Validation ---
read -p "Enter the desired ENV ID (dev, stage, prod, ...): " ENV_ID

# DNS must be compliant with DNS_REGEX
DNS_REGEX="^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"

if [[ ! $ENV_ID =~ $DNS_REGEX ]]; then
    echo "Error: ENV ID '$ENV_ID' is not DNS compliant (use lowercase, numbers, and hyphens)."
    exit 1
fi

# ENV_ID must be present under $DIR_LOC as a directory, if not fail
if [ ! -d "$DIR_LOC/$ENV_ID" ]; then
    echo "Error: Base directory '$DIR_LOC' not found. Please create the '$DIR_PREFIX' folder first using create_env.sh ."
    echo "Error: Environment '$ENV_ID' does not exist in $DIR_LOC."
    exit 1
fi

# --- 3. Tenant ID Input and Validation ---
# Tenant ID must be a positive integer, strictly higher than 0
read -p "Enter the Tenant ID: " TENANT_ID

if [[ ! $TENANT_ID =~ $DNS_REGEX ]]; then
    echo "Error: Tenant ID is not DNS compliant (use lowercase, numbers, and hyphens."
    exit 1
fi

read -p "Enter the integration ID: " INTEGRATION_ID

if [[ ! $INTEGRATION_ID =~ $DNS_REGEX ]]; then
    echo "Error: Integration ID is not DNS compliant (use lowercase, numbers, and hyphens."
    exit 1
fi

read -r -p "Enter the event hub name: " EVENT_HUB_NAME
if [[ -z "$EVENT_HUB_NAME" ]]; then
  echo "Error: event hub name is required." >&2
  exit 1
fi

read -r -p "Enter the event hub primary connection string: " EVENTHUB_CONN_STRING
if [[ -z "$EVENTHUB_CONN_STRING" ]]; then
  echo "Error: event hub primary connection string is required." >&2
  exit 1
fi

echo "-----------------------------------------------------"
echo "Integration: Aure"
echo "Tenant ID: $TENANT_ID"
echo "Environment: $ENV_ID"
echo "Integration ID: $INTEGRATION_ID"
echo "Event hub name: $EVENT_HUB_NAME"
echo "Event hub primary connection: $EVENTHUB_CONN_STRING"
echo "Action: Creating new integration"
echo "-----------------------------------------------------"

read -p "Do you want to add Aure integration $INTEGRATION_ID to tenant $TENANT_ID in $ENV_ID? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborting creation."
    exit 0
fi

vault_check_connect

create_tenant_secret "azure/$INTEGRATION_ID/info" "eventhubname=$EVENT_HUB_NAME" "eventhubconnection=$EVENTHUB_CONN_STRING"

INTEGRATION_TPL="$DIR_LOC/$ENV_ID/helm/loki-base/kustomize/tenants/$TENANT_ID/collectors/$INTEGRATION_ID"
if [ -d "$INTEGRATION_TPL" ]; then
    echo "Error: Integration folder '$INTEGRATION_TPL' already exists for this tenant in this environment."
    exit 1
fi

echo "Creating integration $INTEGRATION_ID at $INTEGRATION_TPL"

cp -r $CLOUDTRAIL_TPL $INTEGRATION_TPL
if [ $? -eq 0 ]; then
    echo "template copied: $INTEGRATION_TPL"
    find "$INTEGRATION_TPL" -type f -exec sed -i '' -e "s#<tenant_id>#$TENANT_ID#g" {} \;
    find "$INTEGRATION_TPL" -type f -exec sed -i '' -e "s#<intergation_id>#$INTEGRATION_ID#g" {} \;
    yq '.resources |= ( . + ["'$INTEGRATION_ID'"] | unique)' -i "$INTEGRATION_TPL/../kustomization.yaml"
else
    echo "Error: Failed to copy directory."
    exit 1
fi

echo "Integration added"