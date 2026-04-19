#!/bin/sh
# Builds the CapRover deployment tarball for Host A.
# Run from anywhere. Output: deploy-host-a.tar in the repo root.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SCRIPT_DIR/../deploy-host-a.tar"

if [ ! -f "$SCRIPT_DIR/config/clients.conf" ]; then
    echo "Error: config/clients.conf not found."
    echo "Copy config/clients.conf.example to config/clients.conf and set your secret first."
    exit 1
fi

tar -cf "$OUT" -C "$SCRIPT_DIR" .
echo "Built: $(cd "$(dirname "$OUT")" && pwd)/deploy-host-a.tar"
echo "Upload this file to CapRover via Apps → [app] → Deployment → Method 2 (Tarball)."
