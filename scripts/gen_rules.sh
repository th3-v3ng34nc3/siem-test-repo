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

# --- 2. ENV ID Input and Validation ---
read -p "Enter the desired ENV ID (dev, stage, prod, ...): " ENV_ID

# DNS must be compliant with DNS_REGEX
DNS_REGEX="^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"

if [[ ! $ENV_ID =~ $DNS_REGEX ]]; then
    echo "Error: ENV ID '$ENV_ID' is not DNS compliant (use lowercase, numbers, and hyphens)."
    exit 1
fi

DIR_LOC="$ENVS_DIR/$DIR_PREFIX"

# ENV_ID must be present under $DIR_LOC as a directory, if not fail
if [ ! -d "$DIR_LOC/$ENV_ID" ]; then
    echo "Error: Base directory '$DIR_LOC' not found. Please create the '$DIR_PREFIX' folder first using create_env.sh ."
    echo "Error: Environment '$ENV_ID' does not exist in $DIR_LOC."
    exit 1
fi

COMMON_RULES_DIR="$DIR_LOC/$ENV_ID/helm/loki-base/rules/common"
TENANTS_DIR="$DIR_LOC/$ENV_ID/helm/loki-base/rules/tenants"

for tenant in $(ls $TENANTS_DIR)
do
    if [[ "$tenant" == "kustomization.yaml" ]]; then
      continue
    fi
    TENANT_AK_ID=$(cat "$DIR_LOC/$ENV_ID/$tenant/info" | grep "SaaS ID" | sed "s/SaaS ID: //g")
    echo Processing tenant $tenant
    kubectl create cm tenant-detection-rules  -n "tenant-$tenant" --dry-run=client -o yaml --from-file="$COMMON_RULES_DIR" > "$TENANTS_DIR/$tenant/detection-rules.yaml"
    kubectl create cm tenant-custom-detection-rules  -n "tenant-$tenant" --dry-run=client -o yaml --from-file="$TENANTS_DIR/$tenant/custom" > "$TENANTS_DIR/$tenant/custom-detection-rules.yaml"
    find "$TENANTS_DIR/$tenant" -type f -exec sed -i '' -e "s#<tenant_id>#$ENV_ID-$tenant#g" {} \;
    find "$TENANTS_DIR/$tenant" -type f -exec sed -i '' -e "s#<accuknox_id>#$TENANT_AK_ID#g" {} \;
done