#!/bin/bash

set -a
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
COMMON_ENVS="$SCRIPT_DIR/common.sh"
source $COMMON_ENVS

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

pushd "$ENVS_DIR/mgmt/$ENV_ID/helm/loki-base"
echo "$ENV_ID" | $SCRIPT_DIR/gen_rules.sh
helmfile init
vault_check_connect
#helmfile write-values
#helmfile destroy
#helmfile sync
helmfile -l name=kustomize sync
popd