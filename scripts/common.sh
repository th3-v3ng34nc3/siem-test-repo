#!/bin/bash
DIR_PREFIX=mgmt
SECRETS_MOUNT_PATH="siem"



vault_check_connect(){
    # --- Vault Connectivity Check ---
    echo "Checking Vault status..."

    # Check if Vault is sealed
    VAULT_SEALED=$(vault status -format=json | jq -r '.sealed')
    if [ "$VAULT_SEALED" != "false" ]; then
        echo "Error: Vault is sealed or unreachable. Please unseal Vault before proceeding."
        exit 1
    fi

    [[ -z "$VAULT_ROLE_ID" ]] && { echo "❌ Error: VAULT_ROLE_ID is not set"; exit 1; }
    [[ -z "$VAULT_SECRET_ID" ]] && { echo "❌ Error: VAULT_SECRET_ID is not set"; exit 1; }

    echo "✅ Environment variables found. Authenticating..."

    export VAULT_TOKEN=$(vault write auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID" -format=json | jq -r '.auth.client_token')

    # Check if user is authenticated/can access Vault
    if ! vault token lookup > /dev/null 2>&1; then
        echo "Error: Vault token is invalid or expired. Please login (vault login)."
        exit 1
    fi
    echo "✅  Authenticated to $VAULT_ADDR..."
}

# Create a Vault KV V2 secret for a specific tenant
# Usage: create_tenant_secret "my-secret-name" "key1=val1" "key2=val2"
create_tenant_secret() {
    local secret_name="$1"
    shift # Remove the first argument (name) so $@ contains only the key-value pairs
    
    # Validation
    if [[ -z "$SECRETS_MOUNT_PATH" ]] || [[ -z "$TENANT_ID" ]] || [[ -z "$ENV_ID" ]]; then
        echo "Error: SECRETS_MOUNT_PATH and TENANT_ID must be set."
        return 1
    fi

    if [[ -z "$secret_name" ]] || [[ $# -eq 0 ]]; then
        echo "Usage: create_tenant_secret <name> <key=value> [key2=value2...]"
        return 1
    fi

    # Construct the full path
    local full_path="${SECRETS_MOUNT_PATH}/${ENV_ID}/tenants/${TENANT_ID}/${secret_name}"

    echo "Creating secret at: $full_path"

    # Execute Vault command
    # Using "$@" ensures that values with spaces are handled correctly
    vault kv put "$full_path" "$@"
}