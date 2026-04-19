#!/usr/bin/env bash
# Deploy a CapRover instance. Called by deploy.sh.
# Packages build artifacts into a tarball and deploys via caprover CLI.
#
# caprover CLI is expected on RADIUS_LAA_BLOCKER_CAPROVER_SSH_HOST (remote).
# If CAPROVER_SSH_HOST is empty, caprover must be available locally.
#
# Usage: scripts/deploy-caprover.sh <host>

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

mkdir -p "$DEPLOY_DIR"
TARBALL="$DEPLOY_DIR/${HOST}.tar.gz"
tar -czf "$TARBALL" -C "$BUILD_DIR" .
echo "Packaged: $TARBALL"

SSH_HOST="${RADIUS_LAA_BLOCKER_CAPROVER_SSH_HOST:-}"

if [[ -n "$SSH_HOST" ]]; then
    # caprover lives on the remote host — scp tarball there and deploy via SSH
    REMOTE_TARBALL="/tmp/${HOST}.tar.gz"
    echo "Copying tarball to $SSH_HOST..."
    scp "$TARBALL" "$SSH_HOST:$REMOTE_TARBALL"

    echo "Deploying to CapRover app $RADIUS_LAA_BLOCKER_CAPROVER_APP via $SSH_HOST..."
    ssh "$SSH_HOST" "
        NVM_DIR=\"\$HOME/.nvm\"
        source \"\$NVM_DIR/nvm.sh\"
        CAPROVER_URL=\"$RADIUS_LAA_BLOCKER_CAPROVER_URL\" \
        CAPROVER_APP=\"$RADIUS_LAA_BLOCKER_CAPROVER_APP\" \
        CAPROVER_APP_TOKEN=\"$RADIUS_LAA_BLOCKER_CAPROVER_TOKEN\" \
        CAPROVER_TAR_FILE=\"$REMOTE_TARBALL\" \
        caprover deploy
        rm -f \"$REMOTE_TARBALL\"
    "
else
    # caprover is available locally
    echo "Deploying to CapRover app $RADIUS_LAA_BLOCKER_CAPROVER_APP..."
    CAPROVER_URL="$RADIUS_LAA_BLOCKER_CAPROVER_URL" \
    CAPROVER_APP="$RADIUS_LAA_BLOCKER_CAPROVER_APP" \
    CAPROVER_APP_TOKEN="$RADIUS_LAA_BLOCKER_CAPROVER_TOKEN" \
    CAPROVER_TAR_FILE="$TARBALL" \
    caprover deploy
fi
