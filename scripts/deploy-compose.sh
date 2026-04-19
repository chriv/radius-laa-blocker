#!/usr/bin/env bash
# Deploy a docker-compose instance. Called by deploy.sh.
# If RADIUS_LAA_BLOCKER_SSH_HOST is empty, deploys to the local machine.
# If set, rsyncs build artifacts to the remote host and runs compose via SSH.
#
# Usage: scripts/deploy-compose.sh <host>

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

SSH_HOST="${RADIUS_LAA_BLOCKER_SSH_HOST:-}"

if [[ -z "$SSH_HOST" ]]; then
    echo "Deploying locally from $BUILD_DIR..."
    docker compose -f "$BUILD_DIR/docker-compose.yml" up --build -d
else
    REMOTE_PATH="${RADIUS_LAA_BLOCKER_REMOTE_PATH:?RADIUS_LAA_BLOCKER_REMOTE_PATH required for remote compose deployment}"
    echo "Deploying to $SSH_HOST:$REMOTE_PATH..."
    rsync -av --delete "$BUILD_DIR/" "$SSH_HOST:$REMOTE_PATH/"
    ssh "$SSH_HOST" "cd '$REMOTE_PATH' && docker compose up --build -d"
fi
