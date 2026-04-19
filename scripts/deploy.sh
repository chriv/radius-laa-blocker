#!/usr/bin/env bash
# Deploy a built host. Dispatches to deploy-caprover.sh or deploy-compose.sh.
# Run build.sh first.
#
# Usage: scripts/deploy.sh <host>

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:?Usage: deploy.sh <host>}"

set -a
# shellcheck source=/dev/null
source "$REPO_ROOT/defaults.env"
# shellcheck source=/dev/null
source "$REPO_ROOT/hosts/$HOST/.env"
set +a

case "$RADIUS_LAA_BLOCKER_DEPLOY_METHOD" in
    caprover)
        exec "$REPO_ROOT/scripts/deploy-caprover.sh" "$HOST"
        ;;
    compose)
        exec "$REPO_ROOT/scripts/deploy-compose.sh" "$HOST"
        ;;
    *)
        echo "ERROR: Unknown RADIUS_LAA_BLOCKER_DEPLOY_METHOD: $RADIUS_LAA_BLOCKER_DEPLOY_METHOD" >&2
        exit 1
        ;;
esac
