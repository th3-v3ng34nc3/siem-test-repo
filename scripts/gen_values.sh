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

pushd "$ENVS_DIR/mgmt/dev/helm/loki-base"
helmfile init
vault_check_connect
#helmfile write-values
#helmfile sync
helmfile -l name=kustomize sync
popd