#!/usr/bin/env bash
# Detect CPU architecture and export BASE_IMAGE and RADIUS_LAA_BLOCKER_CONFIG_PATH.
# Called by build.sh. Sources cleanly: source scripts/detect-arch.sh
#
# Override arch detection by setting RADIUS_LAA_BLOCKER_TARGET_ARCH before sourcing:
#   RADIUS_LAA_BLOCKER_TARGET_ARCH=amd64 source scripts/detect-arch.sh

set -euo pipefail

_arch="${RADIUS_LAA_BLOCKER_TARGET_ARCH:-auto}"

if [[ "$_arch" == "auto" ]]; then
    _arch="$(uname -m)"
fi

case "$_arch" in
    aarch64|arm64)
        export RADIUS_LAA_BLOCKER_ARCH=aarch64
        export RADIUS_LAA_BLOCKER_BASE_IMAGE="debian:bookworm-slim"
        export RADIUS_LAA_BLOCKER_CONFIG_PATH="/etc/freeradius/3.0"
        ;;
    x86_64|amd64)
        export RADIUS_LAA_BLOCKER_ARCH=amd64
        export RADIUS_LAA_BLOCKER_BASE_IMAGE="freeradius/freeradius-server:latest"
        export RADIUS_LAA_BLOCKER_CONFIG_PATH="/etc/freeradius"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $_arch" >&2
        echo "       Set RADIUS_LAA_BLOCKER_TARGET_ARCH to 'aarch64' or 'amd64'" >&2
        exit 1
        ;;
esac
