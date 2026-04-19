#!/usr/bin/env bash
# Deploy a CapRover host. Called by deploy.sh.
# Pushes env vars to CapRover, sets "do not expose as web app", then deploys tarball.
#
# Usage: scripts/deploy-caprover.sh <host>
# Requires: caprover CLI, RADIUS_LAA_BLOCKER_CAPROVER_TOKEN in hosts/<host>/.env

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:?Usage: deploy-caprover.sh <host>}"
BUILD_DIR="$REPO_ROOT/build/$HOST"
DEPLOY_DIR="$REPO_ROOT/deployments"

set -a
# shellcheck source=/dev/null
source "$REPO_ROOT/defaults.env"
# shellcheck source=/dev/null
source "$REPO_ROOT/hosts/$HOST/.env"
set +a

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "ERROR: $BUILD_DIR not found — run build.sh $HOST first" >&2
    exit 1
fi

# TODO (Stage 4): push RADIUS_LAA_BLOCKER_* vars to CapRover app via REST API
# TODO (Stage 4): set "do not expose as web app" via CapRover API

mkdir -p "$DEPLOY_DIR"
TARBALL="$DEPLOY_DIR/${HOST}.tar.gz"
tar -czf "$TARBALL" -C "$BUILD_DIR" .
echo "Packaged: $TARBALL"

# TODO (Stage 4): caprover deploy --appName "$RADIUS_LAA_BLOCKER_CAPROVER_APP" --tarFile "$TARBALL"
echo "STUB: caprover deploy --appName $RADIUS_LAA_BLOCKER_CAPROVER_APP --tarFile $TARBALL"
