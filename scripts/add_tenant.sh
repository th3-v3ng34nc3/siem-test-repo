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

read -p "Enter the Tenant ID (Tenant ID is not Accuknox SaaS ID): " TENANT_ID

if [[ ! $TENANT_ID =~ $DNS_REGEX ]]; then
    echo "Error: Tenant ID is not DNS compliant (use lowercase, numbers, and hyphens."
    exit 1
fi

read -p "Enter the Tenant Name: " TENANT_NAME
read -p "Enter the Tenant Accuknox SaaS ID: " TENANT_AK_ID

# --- 4. Confirmation and Creation ---
TARGET_PATH="$DIR_LOC/$ENV_ID/$TENANT_ID"

echo "-----------------------------------------------------"
echo "Tenant Name: $TENANT_NAME"
echo "Target Name: $TARGET_PATH"
echo "SaaS ID: $TENANT_AK_ID"
echo "Action: Creating new tenant"
echo "-----------------------------------------------------"

read -p "Do you want to add Tenant $TENANT_ID to $ENV_ID? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborting creation."
    exit 0
fi

# Create the folder
if [ -d "$TARGET_PATH" ]; then
    echo "Error: Tenant folder '$TENANT_ID' already exists for this environment."
    exit 1
fi


mkdir -p "$TARGET_PATH"

if [ $? -eq 0 ]; then
    echo "Successfully created: $TARGET_PATH"
else
    echo "Error: Failed to create directory."
    exit 1
fi

vault_check_connect

#USERNAME="$ENV_ID-$TENANT_ID-$(echo $RANDOM | md5sum | awk '{print $1}' | head -c 10)"
USERNAME="$ENV_ID-$TENANT_ID"
PASSWORD=$(openssl rand -base64 32)
INGEST_ENDPOINT=$(echo "$USERNAME $RANDOM $ENV_ID $TENANT_ID" | sha224sum | awk '{print $1}' )

create_tenant_secret "loki_tenant" "username=$USERNAME" "password=$PASSWORD" "endpoint=$INGEST_ENDPOINT"

cat << EOF > $TARGET_PATH/info
Tenant Name: $TENANT_NAME
Endpoint: $INGEST_ENDPOINT
SaaS ID: $TENANT_AK_ID
EOF

echo "Adding k8s templates"
TENANT_TPL="$DIR_LOC/$ENV_ID/helm/loki-base/kustomize/tenants/$TENANT_ID"
TENANT_RULE_TPL="$DIR_LOC/$ENV_ID/helm/loki-base/rules/tenants/$TENANT_ID"

if [ -d "$TENANT_TPL" ]; then
    echo "WARN: Tenant k8s folder '$TENANT_TPL' already exists for this environment. skipping"
else
    cp -r "$ENVS_DIR/templates/tenant-tpl"  "$TENANT_TPL"
    cp -r "$ENVS_DIR/templates/tenant-rules-tpl"  "$TENANT_RULE_TPL"
    yq '.resources |= ( . + ["'$TENANT_ID'"] | unique)' -i "$TENANT_TPL/../kustomization.yaml"
    yq '.resources |= ( . + ["'$TENANT_ID'"] | unique)' -i "$TENANT_RULE_TPL/../kustomization.yaml"
    find "$TENANT_TPL" -type f -exec sed -i '' -e "s#<tenant_id>#$TENANT_ID#g" {} \;
    find "$TENANT_TPL" -type f -exec sed -i '' -e "s#<env_id>#$ENV_ID#g" {} \;
    find "$TENANT_TPL" -type f -exec sed -i '' -e "s#<accuknox_id>#$TENANT_AK_ID#g" {} \;
    find "$TENANT_RULE_TPL" -type f -exec sed -i '' -e "s#<accuknox_id>#$TENANT_AK_ID#g" {} \;
    find "$TENANT_RULE_TPL" -type f -exec sed -i '' -e "s#<tenant_id>#$TENANT_ID#g" {} \;
    find "$TENANT_RULE_TPL" -type f -exec sed -i '' -e "s#<env_id>#$ENV_ID#g" {} \;
fi

echo "Adding tenant to loki for athx & authz"
TENANTS_FILE="$DIR_LOC/$ENV_ID/helm/loki-base/tenants.yaml"
yq -i '.tenants |= ( .  + [{"tenant" : "ref+vault://'"${SECRETS_MOUNT_PATH}/${ENV_ID}/tenants/${TENANT_ID}/loki_tenant/#username"'", "password": "ref+vault://'"${SECRETS_MOUNT_PATH}/${ENV_ID}/tenants/${TENANT_ID}/loki_tenant/#password"'" }] | unique)' "$TENANTS_FILE"
