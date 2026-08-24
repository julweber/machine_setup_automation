#!/bin/bash
set -e

REBUILD=false
for arg in "$@"; do
  [[ "$arg" == "--rebuild" ]] && REBUILD=true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$REBUILD" == true ]]; then
  echo "Rebuilding nanobot image ..."
  docker build -t nanobot .

  echo "Rebuilding nanobot-extended image ..."
  docker build -f Dockerfile.extend -t nanobot-extended .
fi

echo "Restarting nanobot gateway ..."
docker compose down nanobot-gateway
docker compose up -d nanobot-gateway
