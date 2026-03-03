#!/usr/bin/env bash
# ==============================================================================
# setup_nanobot.sh
# ==============================================================================
# Description:
#   Sets up the nanobot environment by cloning the repository, building the
#   Docker image, and initializing the nanobot container via onboarding.
#   Also generates a convenience script (restart_nanobot.sh) for restarting
#   the nanobot gateway.
#
# Usage:
#   bash setup_nanobot.sh
#
# Environment Variables (all optional):
#   NANOBOT_TARGET_REPO_DIRECTORY   Directory to clone the nanobot repository into.
#                                   Default: $HOME/nanobot
#
# Prerequisites:
#   - Docker must be installed and running
#   - git must be available
# ==============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLOURS & HELPERS
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# Optional environment variables
NANOBOT_TARGET_REPO_DIRECTORY="${NANOBOT_TARGET_REPO_DIRECTORY:-$HOME/nanobot}"

# fixed for now - as the default docker-compose file 
# for nanobot is using $HOME/.nanobot as default mount
NANOBOT_SHARED_DIRECTORY="$HOME/.nanobot"

echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

echo "Cloning nanobot repository..."
if [ ! -d "$NANOBOT_TARGET_REPO_DIRECTORY" ]; then
    git clone https://github.com/HKUDS/nanobot "$NANOBOT_TARGET_REPO_DIRECTORY"
else
    echo "nanobot directory already exists, pulling latest changes..."
    cd "$NANOBOT_TARGET_REPO_DIRECTORY" && git pull && cd -
fi

pushd "$NANOBOT_TARGET_REPO_DIRECTORY"

echo "Creating restart_nanobot.sh script..."
cat > restart_nanobot.sh << EOF
#!/bin/bash

set -e

pushd "$NANOBOT_TARGET_REPO_DIRECTORY"
  echo "Stopping nanobot gateway ..."
  docker compose down  nanobot-gateway
  
  echo "Starting nanobot gateway ..."
  docker compose up -d nanobot-gateway
popd
EOF
chmod +x restart_nanobot.sh

echo "Building nanobot Docker image..."
docker build -t nanobot .

echo "Initializing nanobot container ..."
docker compose run --rm nanobot-cli onboard

# user instructions
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  nanobot setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo "Now configure the nanobot config in $NANOBOT_SHARED_DIRECTORY/config.json"

echo "nanobot source were installed to: $NANOBOT_TARGET_REPO_DIRECTORY"
echo "nanobot shared host repo is $NANOBOT_SHARED_DIRECTORY"

echo "Now you can: cd $NANOBOT_TARGET_REPO_DIRECTORY"

echo "Test the LLM API connection:"
echo "docker compose run --rm nanobot-cli agent -m 'Hello!'"
echo "and run the nanobot gateway: ./restart_nanobot.sh"

popd