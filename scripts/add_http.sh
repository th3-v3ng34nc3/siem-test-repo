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
CLOUDTRAIL_TPL="$TPL_LOC/generic-http-tpl"

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

INFO_PATH="$DIR_LOC/$ENV_ID/$TENANT_ID/info"
SERVER_INFO_PATH="$DIR_LOC/$ENV_ID/info"
echo "$SERVER_INFO_PATH"
ENDPOINT=$(cat $INFO_PATH | grep -i Endpoint | awk '{print $2}')
DOMAIN=$(cat $SERVER_INFO_PATH | grep -i server | cut -d"=" -f2)
INTEGRATION_URL="$ENV_ID/$TENANT_ID/$ENDPOINT/$INTEGRATION_ID/push"

echo "-----------------------------------------------------"
echo "Integration: Generic HTTP"
echo "Tenant ID: $TENANT_ID"
echo "Environment: $ENV_ID"
echo "Endpoint: $ENDPOINT"
echo "Integration ID: $INTEGRATION_ID"
echo "Integration URL: $INTEGRATION_URL"
echo "Domain: $DOMAIN"
echo "Action: Creating new integration"
echo "-----------------------------------------------------"

read -p "Do you want to add Generic HTTP integration $INTEGRATION_ID to tenant $TENANT_ID in $ENV_ID? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborting creation."
    exit 0
fi

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
    find "$INTEGRATION_TPL" -type f -exec sed -i '' -e "s#<siem_env>#$ENV_ID#g" {} \;
    find "$INTEGRATION_TPL" -type f -exec sed -i '' -e "s#<tenant_endpoint>#$ENDPOINT#g" {} \;
    find "$INTEGRATION_TPL" -type f -exec sed -i '' -e "s#<siem_domain>#$DOMAIN#g" {} \;
    yq '.resources |= ( . + ["'$INTEGRATION_ID'"] | unique)' -i "$INTEGRATION_TPL/../kustomization.yaml"
else
    echo "Error: Failed to copy directory."
    exit 1
fi

echo "Integration added"