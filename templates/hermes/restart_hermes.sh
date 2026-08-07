#!/bin/bash
# Simple restart script for Hermes services (gateway + dashboard)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping Hermes gateway ..."
docker compose down hermes-gateway

echo "Stopping Hermes dashboard ..."
docker compose down hermes-dashboard 2>/dev/null || true

echo "Starting Hermes gateway ..."
docker compose up -d hermes-gateway

echo "Starting Hermes dashboard ..."
docker compose up -d hermes-dashboard
