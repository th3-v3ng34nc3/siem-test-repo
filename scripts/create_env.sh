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

# Define the base location using the git root
# Note: Ensure $DIR_PREFIX is exported or defined elsewhere in your environment
DIR_LOC="$ENVS_DIR/$DIR_PREFIX"

# --- Confirmation Logic ---
echo "You are creating a new SIEM environment, are you sure? (Type 'yes' to proceed)"
read -r confirmation

# Only 'yes' is accepted, else exit
if [ "$confirmation" != "yes" ]; then
    echo "Operation cancelled by user."
    exit 1
fi

if [[ -z "$AK_TOKEN" ]]; then
  echo "Export Accuknox token in a variable called AK_TOKEN"
  echo "Error: AK_TOKEN is required." >&2
  exit 1
fi

# --- Input and DNS Validation ---
echo "Enter the env name:"
read -r ENV_NAME

# Validation: DNS compliant (RFC 1123)
# - Only lowercase letters, numbers, and hyphens
# - Must start and end with an alphanumeric character
# - Length between 1 and 63 characters
DNS_REGEX="^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"

if [[ ! $ENV_NAME =~ $DNS_REGEX ]]; then
    echo "Error: Invalid environment name. Must be DNS compliant (lowercase, numbers, hyphens, no trailing hyphens)."
    exit 1
fi

echo "Enter the env buckets regions:"
read -r REGION

echo "Enter the env chunks bucket name:"
read -r CHUNKS

echo "Enter the env ruler bucket name:"
read -r RULER

echo "Enter the env admin bucket name:"
read -r ADMIN

echo "Enter the env AWS access key ID with admin prems on all above 3 buckets:"
read -r LOKI_BUCKET_ACCESS_KEY

echo "Enter the env AWS secret access key:"
read -r LOKI_BUCKET_SECRET_KEY

echo "Enter the ingestion protocol (HTTP/HTTPS):"
read -r PROTOCOL
# Convert to uppercase for easier comparison
PROTOCOL_UPPER=$(echo "$PROTOCOL" | tr '[:lower:]' '[:upper:]')

if [[ "$PROTOCOL_UPPER" != "HTTP" && "$PROTOCOL_UPPER" != "HTTPS" ]]; then
    echo "Error: Invalid protocol. Must be HTTP or HTTPS."
    exit 1
fi

PROTOCOL_UPPER=$(echo $PROTOCOL_UPPER | tr  "[:upper:]" "[:lower:]")

echo "Enter the SIEM ingestion URL (e.g., siem.example.com):"
read -r URL
# Simple regex for domain/hostname validation
URL_REGEX="^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"

if [[ ! $URL =~ $URL_REGEX ]]; then
    echo "Error: Invalid URL format."
    exit 1
fi


echo "Enter the ingestion Port (1-65535):"
read -r PORT

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Error: Invalid Port. Must be a number between 1 and 65535."
    exit 1
fi

echo "Enter Azure Mutex storage account primaryConnection string (create a storage account):"
read -r PRIMARYCONN

echo "Enter Azure Mutex prefix:"
read -r PREFIX

if [[ ! "$PREFIX" =~ ^[a-z]+$ ]]; then
    echo "Error: Invalid Prefix. Must be only lowercase alphabet."
    exit 1
fi

echo "Enter Accuknox alerts endpoint url (e.g: https://cwpp.demo.accuknox.com/webhook/alert):"
read -r AK_ENDPOINT

vault_check_connect

K8S_CLUSTER_ADDR=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
K8S_CLUSTER_CERT=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

echo "-----------------------------------------------------"
echo "Env Name: $ENV_NAME"
echo "Vault: $VAULT_ADDR"
echo "k8s: $K8S_CLUSTER_ADDR"
echo "URL: $AK_ENDPOINT"
echo "Action: Creating new siem env"
echo "-----------------------------------------------------"

read -p "Do you want to add env $ENV_NAME ? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborting creation."
    exit 0
fi

# --- Vault Mount Creation ---
MOUNT_TARGET="$SECRETS_MOUNT_PATH/$ENV_NAME"

echo "Attempting to create secret mount on ==> $MOUNT_TARGET"

# Check if mount exists using jq to parse the secrets list
if vault secrets list -format=json | jq -e ".\"$MOUNT_TARGET/\"" > /dev/null; then
    echo "Warning: Vault mount '$MOUNT_TARGET' already exists."
else
    echo "Creating KV-V2 mount at $MOUNT_TARGET..."
    vault secrets enable -path="$MOUNT_TARGET" kv-v2
fi

vault kv put "$MOUNT_TARGET/server" "server=$URL" "port=$PORT" "protocol=$PROTOCOL_UPPER"
vault kv put "$MOUNT_TARGET/mutex/AZURE-STORAGEACCOUNT" "prefix=$PREFIX" "primaryconnection=$PRIMARYCONN"
vault kv put "$MOUNT_TARGET/storage/backend" "region=$REGION" "chunks=$CHUNKS" "admin=$ADMIN" "ruler=$RULER" "accessKeyId=$LOKI_BUCKET_ACCESS_KEY" "secretAccessKey=$LOKI_BUCKET_SECRET_KEY"
vault kv put "$MOUNT_TARGET/accuknox/login" "token=$AK_TOKEN" "endpoint=$AK_ENDPOINT"

SIEM_BACKEND_PATH="$MOUNT_TARGET/storage/backend"

if [ $? -eq 0 ]; then
    echo "Success: Environment info added in vault at  $MOUNT_TARGET/server"
else
    echo "Error: Failed to add env info to vault."
    exit 1
fi

# --- Directory Creation ---
# Create the target directory path
TARGET_PATH="$DIR_LOC/$ENV_NAME"

if [ -d "$TARGET_PATH" ]; then
    echo "Error: Directory '$TARGET_PATH' already exists."
    exit 1
fi

mkdir -p "$TARGET_PATH/helm"


if [ $? -eq 0 ]; then
    echo "Success: Environment created at $TARGET_PATH"
    cat << EOF > "$TARGET_PATH/info"
server=$URL
port=$PORT
protocol=$PROTOCOL_UPPER
EOF
else
    echo "Error: Failed to create directory."
    exit 1
fi

VAULT_POLICY_NAME="siem-$ENV_NAME-external-secrets"

cp -r $ENVS_DIR/templates/loki-base $TARGET_PATH/helm/
sed -i "" "s#<siem_backend_path>#$SIEM_BACKEND_PATH#g" "$TARGET_PATH/helm/loki-base/helmfile.yaml"
sed -i "" "s#<siem_mount_path>#$MOUNT_TARGET#g" "$TARGET_PATH/helm/loki-base/helmfile.yaml"
sed -i "" "s#<siem_env>#$ENV_NAME#g" "$TARGET_PATH/helm/loki-base/helmfile.yaml"
sed -i "" "s#<vault_addr>#$VAULT_ADDR#g" "$TARGET_PATH/helm/loki-base/kustomize/externalsecrets.yaml"
sed -i "" "s#<vault_path>#$MOUNT_TARGET#g" "$TARGET_PATH/helm/loki-base/kustomize/externalsecrets.yaml"
sed -i "" "s#<vault_role>#$VAULT_POLICY_NAME#g" "$TARGET_PATH/helm/loki-base/kustomize/externalsecrets.yaml"
sed -i "" "s#<siem_domain>#$URL#g" "$TARGET_PATH/helm/loki-base/kustomize/gateway.yaml"

echo "Establishing trust between $K8S_CLUSTER_ADDR and $VAULT_ADDR"
vault auth enable -path="$MOUNT_TARGET" kubernetes

if [ $? -eq 0 ]; then
    echo "Success: Auth backend $MOUNT_TARGET was added to vault"
else
    echo "Error: Failed to add auth backend $MOUNT_TARGET to vault."
    exit 1
fi

vault write "auth/$MOUNT_TARGET/config" \
    kubernetes_host="$K8S_CLUSTER_ADDR" \
    kubernetes_ca_cert="$K8S_CLUSTER_CERT"

if [ $? -eq 0 ]; then
    echo "Success: Auth backend $MOUNT_TARGET was configured"
else
    echo "Error: Failed to configure auth backend $MOUNT_TARGET to vault."
    exit 1
fi

cat << EOF > external-secrets-vault-pol.hcl
path "$MOUNT_TARGET/data/*" {
  capabilities = ["read"]
}
EOF

vault policy write "$VAULT_POLICY_NAME" external-secrets-vault-pol.hcl

if [ $? -eq 0 ]; then
    echo "Success: $VAULT_POLICY_NAME policy was added to vault"
else
    echo "Error: Failed to add $VAULT_POLICY_NAME policy to vault."
    exit 1
fi

vault write "auth/$MOUNT_TARGET/role/$VAULT_POLICY_NAME" \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies="$VAULT_POLICY_NAME,default" \
    ttl=24h

if [ $? -eq 0 ]; then
    echo "Success: Auth backend role $VAULT_POLICY_NAME was created"
else
    echo "Error: Failed to create auth backend role $VAULT_POLICY_NAME."
    exit 1
fi


echo "Env $ENV_NAME have been added"
echo "Creating the canary tenant"
cat <<EOF | $SCRIPT_DIR/add_tenant.sh
$ENV_NAME
canary-user
$ENV_NAME canary user
y
EOF
if [ $? -eq 0 ]; then
    echo "Success: Canary user was created"
else
    echo "Error: Failed to create canary user."
    exit 1
fi
echo "You need to add tenants as a next step"
echo "After adding tenants you will need to generate the required manifests"
