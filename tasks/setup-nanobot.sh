#!/usr/bin/env bash
# ==============================================================================
# setup-nanobot.sh
# ==============================================================================
# Description:
#   Sets up the nanobot environment by cloning the repository, building the
#   Docker image, and initializing the nanobot container via onboarding.
#   Also generates a convenience script (restart_nanobot.sh) for restarting
#   the nanobot gateway.
#
# Usage:
#   bash setup-nanobot.sh
#
#   Optionally override the clone destination:
#     NANOBOT_TARGET_REPO_DIRECTORY=/opt/nanobot bash setup-nanobot.sh
#
# Key Steps:
#   1. Verify that Docker is installed and available on PATH.
#   2. Clone the nanobot repository (https://github.com/HKUDS/nanobot) into
#      NANOBOT_TARGET_REPO_DIRECTORY, or pull the latest changes if the
#      directory already exists.
#   3. Generate a restart_nanobot.sh convenience script inside the repository
#      directory that stops and restarts the nanobot-gateway Docker service.
#      Supports --rebuild flag to rebuild both Docker images before restarting.
#   4. Build the upstream nanobot Docker image (tagged "nanobot") from the
#      cloned source.
#   5. Copy templates/nanobot/Dockerfile.extend into the clone directory and
#      build the extended image (tagged "nanobot-extended") on top of it.
#   6. Write a docker-compose.override.yml into the clone directory so that
#      both services (nanobot-gateway and nanobot-cli) use nanobot-extended.
#   7. Run the nanobot onboarding flow via:
#        docker compose run --rm nanobot-cli onboard
#      This initialises the shared config directory (NANOBOT_SHARED_DIRECTORY).
#   8. Print post-setup instructions, including how to configure the API key
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
#       A helper script that stops and restarts the nanobot-gateway service.
#       Accepts an optional --rebuild flag: rebuilds both the upstream nanobot
#       image and the nanobot-extended image before restarting the gateway.
#       Created with execute permissions during setup.
#
#   <NANOBOT_TARGET_REPO_DIRECTORY>/Dockerfile.extend
#       Copied from templates/nanobot/Dockerfile.extend in this repo.
#       Defines the custom layer (extra apt/pip/npm packages) built on top of
#       the upstream nanobot image.
#
#   <NANOBOT_TARGET_REPO_DIRECTORY>/docker-compose.override.yml
#       Generated automatically. Overrides the image used by both Compose
#       services to nanobot-extended so the gateway and CLI both run the
#       extended image. The upstream docker-compose.yml is left untouched.
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

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'

# Absolute path to this script's directory (must be resolved before any pushd)
SCRIPT_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    LATEST_TAG=$(git -C "$NANOBOT_TARGET_REPO_DIRECTORY" describe --tags "$(git -C "$NANOBOT_TARGET_REPO_DIRECTORY" rev-list --tags --max-count=1)")
    echo "Checking out latest release tag: $LATEST_TAG"
    git -C "$NANOBOT_TARGET_REPO_DIRECTORY" checkout "$LATEST_TAG"
else
    echo "nanobot directory already exists, fetching latest tags..."
    git -C "$NANOBOT_TARGET_REPO_DIRECTORY" fetch --tags
    LATEST_TAG=$(git -C "$NANOBOT_TARGET_REPO_DIRECTORY" describe --tags "$(git -C "$NANOBOT_TARGET_REPO_DIRECTORY" rev-list --tags --max-count=1)")
    echo "Checking out latest release tag: $LATEST_TAG"
    git -C "$NANOBOT_TARGET_REPO_DIRECTORY" checkout "$LATEST_TAG"
fi

pushd "$NANOBOT_TARGET_REPO_DIRECTORY"

echo "Creating restart_nanobot.sh script..."
cat > restart_nanobot.sh << 'RESTART_EOF'
#!/bin/bash
# Stops and restarts the nanobot-gateway.
# Usage:
#   ./restart_nanobot.sh            # restart only
#   ./restart_nanobot.sh --rebuild  # rebuild both images, then restart

set -e

REBUILD=false
for arg in "$@"; do
  [[ "$arg" == "--rebuild" ]] && REBUILD=true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pushd "$SCRIPT_DIR"

if [[ "$REBUILD" == true ]]; then
  echo "Rebuilding upstream nanobot image ..."
  docker build -t nanobot .

  echo "Rebuilding nanobot-extended image ..."
  docker build -f Dockerfile.extend -t nanobot-extended .
fi

echo "Stopping nanobot gateway ..."
docker compose down nanobot-gateway

echo "Starting nanobot gateway ..."
docker compose up -d nanobot-gateway

popd
RESTART_EOF
chmod +x restart_nanobot.sh

echo "Building nanobot Docker image..."
docker build -t nanobot .

# -- Step: copy Dockerfile.extend from this repo's templates ------------------
DOCKERFILE_EXTEND_SRC="$SCRIPT_REPO_DIR/../templates/nanobot/Dockerfile.extend"

if [ ! -f "$DOCKERFILE_EXTEND_SRC" ]; then
    echo -e "${RED}Error: Dockerfile.extend not found at $DOCKERFILE_EXTEND_SRC${RESET}"
    exit 1
fi

echo "Copying Dockerfile.extend into nanobot repo ..."
cp "$DOCKERFILE_EXTEND_SRC" Dockerfile.extend

# -- Step: build the extended image -------------------------------------------
echo "Building nanobot-extended Docker image ..."
docker build -f Dockerfile.extend -t nanobot-extended .

# -- Step: write docker-compose.override.yml ----------------------------------
echo "Writing docker-compose.override.yml ..."
cat > docker-compose.override.yml << 'COMPOSE_EOF'
# Auto-generated by setup-nanobot.sh -- do not edit by hand.
# Overrides both services to use the locally-built nanobot-extended image
# (which layers extra tools on top of the upstream nanobot image).
# Re-run setup-nanobot.sh or use restart_nanobot.sh --rebuild to refresh.
services:
  nanobot-gateway:
    image: nanobot-extended
    build: {}
  nanobot-cli:
    image: nanobot-extended
    build: {}
COMPOSE_EOF

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