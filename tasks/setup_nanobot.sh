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
#   Optionally override the clone destination:
#     NANOBOT_TARGET_REPO_DIRECTORY=/opt/nanobot bash setup_nanobot.sh
#
# Key Steps:
#   1. Verify that Docker is installed and available on PATH.
#   2. Clone the nanobot repository (https://github.com/HKUDS/nanobot) into
#      NANOBOT_TARGET_REPO_DIRECTORY, or pull the latest changes if the
#      directory already exists.
#   3. Generate a restart_nanobot.sh convenience script inside the repository
#      directory that stops and restarts the nanobot-gateway Docker service.
#   4. Build the nanobot Docker image (tagged "nanobot") from the cloned source.
#   5. Run the nanobot onboarding flow via:
#        docker compose run --rm nanobot-cli onboard
#      This initialises the shared config directory (NANOBOT_SHARED_DIRECTORY).
#   6. Print post-setup instructions, including how to configure the API key
#      and test the LLM connection.
#
# Environment Variables:
#   NANOBOT_TARGET_REPO_DIRECTORY   (optional) Directory to clone the nanobot
#                                   repository into.
#                                   Default: $HOME/nanobot
#
#   NANOBOT_SHARED_DIRECTORY        (internal, not overridable) Host directory
#                                   mounted into the nanobot containers for
#                                   shared config and data. Matches the default
#                                   mount path used by the upstream
#                                   docker-compose.yml.
#                                   Fixed value: $HOME/.nanobot
#
# Generated Files:
#   <NANOBOT_TARGET_REPO_DIRECTORY>/restart_nanobot.sh
#       A helper script that runs `docker compose down nanobot-gateway` followed
#       by `docker compose up -d nanobot-gateway`. Created with execute
#       permissions during setup.
#
# Prerequisites / Dependencies:
#   - bash  (version 4+ recommended; uses set -euo pipefail)
#   - docker  (must be installed, running, and accessible without sudo)
#   - docker compose  (v2 plugin or standalone; used for run / up / down)
#   - git  (must be available on PATH for cloning / pulling the repo)
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