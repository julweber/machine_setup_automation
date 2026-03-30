#!/bin/bash
# Simple restart script for hermes-gateway service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping Hermes gateway ..."
docker compose down hermes-gateway

echo "Starting Hermes gateway ..."
docker compose up -d hermes-gateway
