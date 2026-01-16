#!/bin/bash


set -a
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
COMMON_ENVS="$SCRIPT_DIR/common.sh"
source $COMMON_ENVS


# --- Security Warning and Confirmation ---
CONFIRMATION_VAL=$RANDOM
echo "****************************************************************"
echo "WARNING: This script will print sensitive information (secrets)."
echo "****************************************************************"
read -p "To proceed, type exactly: I confirm $CONFIRMATION_VAL
> " USER_CONFIRMATION

if [[ "$USER_CONFIRMATION" != "I confirm $CONFIRMATION_VAL" ]]; then
    echo "Error: Confirmation failed. Operation cancelled."
    exit 1
fi

read -p "Enter the desired ENV ID (dev, stage, prod, ...): " ENV_ID
# DNS must be compliant with DNS_REGEX
DNS_REGEX="^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"
if [[ ! $ENV_ID =~ $DNS_REGEX ]]; then
    echo "Error: ENV ID '$ENV_ID' is not DNS compliant (use lowercase, numbers, and hyphens)."
    exit 1
fi


read -p "Enter the Tenant ID: " TENANT_ID
if [[ ! $TENANT_ID =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Tenant ID must be a positive integer (greater than 0 and cannot start with 0)."
    exit 1
fi

vault_check_connect

full_path="tenants/${TENANT_ID}/loki_tenant"

if ! vault kv get -mount="${SECRETS_MOUNT_PATH}/${ENV_ID}" "$full_path" &> /dev/null ; then
    echo "Error: Secret at path '$full_path' does not exist or is inaccessible."
    exit 1
fi

SECRET=(vault kv get -mount="${SECRETS_MOUNT_PATH}/${ENV_ID}" "$full_path")

