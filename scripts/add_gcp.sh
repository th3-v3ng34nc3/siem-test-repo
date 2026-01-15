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

# Define the base location using the git root
DIR_LOC="$ENVS_DIR/$DIR_PREFIX"
TPL_LOC="$ENVS_DIR/templates"
CLOUDTRAIL_TPL="$TPL_LOC/gcp-collector-tpl"

echo "Export the service account key  in a variable called SA_KEY_B64(IN BASE64 FORMAT!!!!)"
if [[ -z "$SA_KEY_B64" ]]; then
  echo "Error: SA_KEY_B64 is required." >&2
  exit 1
fi

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

read -r -p "Enter the project ID: " PROJECT_ID
if [[ -z "$PROJECT_ID" ]]; then
  echo "Error: project ID is required." >&2
  exit 1
fi

read -r -p "Enter the subscription name: " SUB_NAME
if [[ -z "$SUB_NAME" ]]; then
  echo "Error: subscription name is required." >&2
  exit 1
fi

read -r -p "Enter the Topic name: " TOPIC_NAME
if [[ -z "$TOPIC_NAME" ]]; then
  echo "Error: Topic name is required." >&2
  exit 1
fi



echo "-----------------------------------------------------"
echo "Integration: GCP"
echo "Tenant ID: $TENANT_ID"
echo "Environment: $ENV_ID"
echo "Integration ID: $INTEGRATION_ID"
echo "Project ID: $PROJECT_ID"
echo "Subscription: $SUB_NAME"
echo "Topic: $TOPIC_NAME"
echo "Action: Creating new integration"
echo "-----------------------------------------------------"

read -p "Do you want to add GCP integration $INTEGRATION_ID to tenant $TENANT_ID in $ENV_ID? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborting creation."
    exit 0
fi

vault_check_connect

create_tenant_secret "gcp/$INTEGRATION_ID/info" "project=$PROJECT_ID" "topic=$TOPIC_NAME" "subscription=$SUB_NAME"
create_tenant_secret "gcp/$INTEGRATION_ID/key" "key=$SA_KEY_B64"

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