#!/usr/bin/env bash
# Build the Apptainer SIF for the upstream R preprocessing step, locally,
# then copy to DCC. Run on the laptop (or any host with apptainer installed).
#
# Usage:
#   bash scripts/build_dcc_sif.sh           # build only
#   bash scripts/build_dcc_sif.sh push      # build + scp to DCC
set -euo pipefail

SIF="${SIF:-$HOME/tmp/tensorsig-data.sif}"
DCC_HOST="${DCC_HOST:-dcc-login.oit.duke.edu}"
DCC_DEST="${DCC_DEST:-/cwork/sr110/test-breast-xplus/}"

mkdir -p "$(dirname "$SIF")"

if [[ ! -f "$SIF" ]]; then
    echo "Building $SIF from docker.io/sagar87/tensorsignatures-data:latest"
    apptainer build "$SIF" docker://sagar87/tensorsignatures-data:latest
else
    echo "$SIF already exists; skipping build"
fi

ls -lh "$SIF"

if [[ "${1:-}" == "push" ]]; then
    echo "Pushing $SIF to $DCC_HOST:$DCC_DEST"
    ssh "$DCC_HOST" "mkdir -p $DCC_DEST"
    rsync -avz --progress "$SIF" "$DCC_HOST:$DCC_DEST/"
fi
