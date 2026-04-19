#!/usr/bin/env bash
# Build a host's deployment artifacts from templates.
# Output goes to build/<host>/ (gitignored).
#
# Usage: scripts/build.sh <host>
#   host: directory name under hosts/ (e.g. host-1)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:?Usage: build.sh <host>}"
HOST_DIR="$REPO_ROOT/hosts/$HOST"
BUILD_DIR="$REPO_ROOT/build/$HOST"

if [[ ! -d "$HOST_DIR" ]]; then
    echo "ERROR: No host directory found at $HOST_DIR" >&2
    exit 1
fi
if [[ ! -f "$HOST_DIR/.env" ]]; then
    echo "ERROR: $HOST_DIR/.env not found — copy .env.example and fill in values" >&2
    exit 1
fi

# Load defaults, then overlay host-specific values
set -a
# shellcheck source=/dev/null
source "$REPO_ROOT/defaults.env"
# shellcheck source=/dev/null
source "$HOST_DIR/.env"
set +a

# Detect/set architecture variables
# shellcheck source=scripts/detect-arch.sh
source "$REPO_ROOT/scripts/detect-arch.sh"

echo "Building $HOST (arch=$RADIUS_LAA_BLOCKER_ARCH, method=$RADIUS_LAA_BLOCKER_DEPLOY_METHOD)"

# Clean and recreate build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/config/sites-available"

# Variables to substitute (explicit list keeps FreeRADIUS ${var} syntax intact)
SUBST_VARS='$RADIUS_LAA_BLOCKER_SECRET:$RADIUS_LAA_BLOCKER_PORT:$RADIUS_LAA_BLOCKER_CONFIG_PATH:$RADIUS_LAA_BLOCKER_SYSLOG_HOST:$RADIUS_LAA_BLOCKER_SYSLOG_PORT'

# Generate config files (same for all deploy methods)
envsubst "$SUBST_VARS" \
    < "$REPO_ROOT/template/config/clients.conf.tmpl" \
    > "$BUILD_DIR/config/clients.conf"

cp "$REPO_ROOT/template/config/sites-available/default.tmpl" \
   "$BUILD_DIR/config/sites-available/default"

# Select and generate deployment-method-specific files
case "$RADIUS_LAA_BLOCKER_DEPLOY_METHOD" in
    caprover)
        cp "$REPO_ROOT/template/captain-definition.tmpl" "$BUILD_DIR/captain-definition"
        cp "$REPO_ROOT/template/Dockerfile.caprover-${RADIUS_LAA_BLOCKER_ARCH}.tmpl" \
           "$BUILD_DIR/Dockerfile"
        ;;
    compose)
        envsubst "$SUBST_VARS" \
            < "$REPO_ROOT/template/docker-compose.tmpl" \
            > "$BUILD_DIR/docker-compose.yml"
        # Remove syslog logging block if SYSLOG_HOST is not configured
        if [[ -z "${RADIUS_LAA_BLOCKER_SYSLOG_HOST:-}" ]]; then
            sed -i.bak '/^    logging:/,/^        tag:/d' "$BUILD_DIR/docker-compose.yml"
            rm -f "$BUILD_DIR/docker-compose.yml.bak"
        fi
        cp "$REPO_ROOT/template/Dockerfile.compose-${RADIUS_LAA_BLOCKER_ARCH}.tmpl" \
           "$BUILD_DIR/Dockerfile"
        ;;
    *)
        echo "ERROR: Unknown RADIUS_LAA_BLOCKER_DEPLOY_METHOD: $RADIUS_LAA_BLOCKER_DEPLOY_METHOD" >&2
        exit 1
        ;;
esac

echo "Build complete: $BUILD_DIR"
