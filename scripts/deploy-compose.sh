#!/usr/bin/env bash
# Deploy a docker-compose host via rsync + SSH. Called by deploy.sh.
#
# Usage: scripts/deploy-compose.sh <host>
# Requires in hosts/<host>/.env:
#   RADIUS_LAA_BLOCKER_SSH_HOST  — user@hostname
#   RADIUS_LAA_BLOCKER_REMOTE_PATH — absolute path on target host

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:?Usage: deploy-compose.sh <host>}"
BUILD_DIR="$REPO_ROOT/build/$HOST"

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

SSH_HOST="${RADIUS_LAA_BLOCKER_SSH_HOST:?RADIUS_LAA_BLOCKER_SSH_HOST not set in hosts/$HOST/.env}"
REMOTE_PATH="${RADIUS_LAA_BLOCKER_REMOTE_PATH:?RADIUS_LAA_BLOCKER_REMOTE_PATH not set in hosts/$HOST/.env}"

# TODO (Stage 4): rsync "$BUILD_DIR/" "$SSH_HOST:$REMOTE_PATH/"
# TODO (Stage 4): ssh "$SSH_HOST" "cd $REMOTE_PATH && docker compose up --build -d"
echo "STUB: rsync $BUILD_DIR/ $SSH_HOST:$REMOTE_PATH/"
echo "STUB: ssh $SSH_HOST 'cd $REMOTE_PATH && docker compose up --build -d'"
