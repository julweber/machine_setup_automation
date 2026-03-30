#!/usr/bin/env bash
# ==============================================================================
# setup-hermes.sh
# ===============================================================================
# Description:
#   Sets up the Hermes Agent environment using the official prebuilt Docker image.
#   Creates a target directory, generates configuration files from templates,
#   and provides convenience scripts for management.
#
# Usage:
#   bash setup-hermes.sh
#
#   Optionally override the target directory:
#     HERMES_TARGET_REPO_DIRECTORY=/opt/hermes bash setup-hermes.sh
#
# Key Steps:
#   1. Verify that Docker is installed and available on PATH.
#   2. Create target directory at /srv/hermes (HERMES_TARGET_REPO_DIRECTORY).
#   3. Pull the official Hermes prebuilt image (nousresearch/hermes-agent).
#   4. Copy docker-compose.yml from templates/hermes/docker-compose.yml.
#   5. Generate .env template file for API key configuration.
#   6. Copy restart_hermes.sh convenience script from template.
#   7. Provide post-setup instructions including how to run the setup wizard
#      and start the gateway once configured.
#
# Environment Variables:
#   HERMES_TARGET_REPO_DIRECTORY    (optional) Directory to set up Hermes.
#                                   Default: /srv/hermes
#
# Generated Files:
#   <HERMES_TARGET_REPO_DIRECTORY>/docker-compose.yml
#       Defines hermes-gateway, hermes-chat, and hermes-setup services.
#       Uses official prebuilt image nousresearch/hermes-agent.
#       Mounts HERMES_DATA_DIRECTORY -> /opt/data (container path).
#
#   <HERMES_TARGET_REPO_DIRECTORY>/restart_hermes.sh
#       A helper script that stops and restarts the hermes-gateway service.
#
# Prerequisites / Dependencies:
#   - bash  (version 4+ recommended; uses set -euo pipefail)
#   - docker  (must be installed, running, and accessible without sudo)
#   - docker compose  (v2 plugin or standalone; used for up / down / run)
# ==============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLOURS & HELPERS
# ─────────────────────────────────────────────────────────────────────────────

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────

BUILD_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --build-only)
            BUILD_ONLY=true
            ;;
        *)
            echo -e "${RED}Error: Unknown argument: $arg${RESET}" >&2
            echo "Usage: $0 [--build-only]" >&2
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# PATHS
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/../templates/hermes"

# Optional environment variables - default to /srv/hermes as per spec
HERMES_TARGET_REPO_DIRECTORY="${HERMES_TARGET_REPO_DIRECTORY:-/srv/hermes}"

# Hermes data directory (matches official pattern: ~/.hermes in Docker docs)
HERMES_DATA_DIRECTORY="${HERMES_TARGET_REPO_DIRECTORY}/.hermes"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Check Docker installation
# ─────────────────────────────────────────────────────────────────────────────

echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed. Please install Docker first.${RESET}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running. Start Docker and try again.${RESET}"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Create target directory (if it doesn't exist)
# ─────────────────────────────────────────────────────────────────────────────

echo "Setting up target directory..."
if [ ! -d "$HERMES_TARGET_REPO_DIRECTORY" ]; then
    sudo mkdir -p "$HERMES_TARGET_REPO_DIRECTORY"
    echo "Created directory: $HERMES_TARGET_REPO_DIRECTORY"
else
    echo "Target directory already exists: $HERMES_TARGET_REPO_DIRECTORY"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Pull the official Hermes prebuilt image
# ─────────────────────────────────────────────────────────────────────────────

echo "Pulling official Hermes prebuilt image..."
docker pull nousresearch/hermes-agent:latest

if [[ "$BUILD_ONLY" == true ]]; then
    echo ""
    echo -e "${GREEN}${BOLD}Official Hermes image pulled successfully.${RESET}"
    echo "Exiting (--build-only mode)."
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Copy docker-compose.yml from template
# ─────────────────────────────────────────────────────────────────────────────

echo "Copying docker-compose.yml from template..."
sudo cp "${TEMPLATES_DIR}/docker-compose.yml" "$HERMES_TARGET_REPO_DIRECTORY/docker-compose.yml"



# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: Copy restart_hermes.sh from template
# ─────────────────────────────────────────────────────────────────────────────

echo "Copying restart_hermes.sh from template..."
sudo cp "${TEMPLATES_DIR}/restart_hermes.sh" "$HERMES_TARGET_REPO_DIRECTORY/restart_hermes.sh"
sudo chmod +x "$HERMES_TARGET_REPO_DIRECTORY/restart_hermes.sh"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8: Post-setup instructions (user must configure before starting)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Hermes Agent setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

# ── Configuration instructions ──────────────────────────────────────────────
echo -e "${YELLOW}📁 Your files:${RESET}"
echo "   Data directory:   $HERMES_DATA_DIRECTORY"
echo "   Repository:       $HERMES_TARGET_REPO_DIRECTORY"
echo "   Docker image:     nousresearch/hermes-agent:latest"
echo ""

# ── Setup wizard instructions ───────────────────────────────────────────────
echo -e "${YELLOW}🚀 Step 1: Run the setup wizard to configure Hermes:${RESET}"
echo ""
echo "   cd $HERMES_TARGET_REPO_DIRECTORY"
echo "   docker compose run -it hermes-setup"
echo "   # Press Ctrl+D when finished"
echo ""

# ── Start the gateway instructions ───────────────────────────────────────────
echo -e "${YELLOW}💬 Step 2: Start chatting with Hermes:${RESET}"
echo ""
echo "   Option A — Use the hermes-chat service:"
echo "     cd $HERMES_TARGET_REPO_DIRECTORY"
echo "     docker compose run -it hermes-chat"
echo ""
echo "   Option B — Start the gateway and attach:"
echo "     ./restart_hermes.sh"
echo "     docker compose run -it hermes-gateway chat"
echo ""

# ── Command reference ───────────────────────────────────────────────────────
echo -e "${YELLOW}📖 Common commands:${RESET}"

echo ""
echo "   ${BOLD}hermes help:${RESET}"
echo "     docker compose run -it hermes-gateway --help   # display help"
echo ""

echo ""
echo "   ${BOLD}Gateway management:${RESET}"
echo "     ./restart_hermes.sh              # Start/restart gateway"
echo "     docker compose logs -f hermes-gateway  # View logs"
echo ""

echo "   ${BOLD}Interactive session:${RESET}"
echo "     docker compose run -it hermes-chat # Full TUI interface"
echo ""

echo "   ${BOLD}Model selection:${RESET}"
echo "     docker compose run -it hermes-chat model # configure chat model"
echo ""

echo "   ${BOLD}Messaging setup:${RESET}"
echo "     docker compose run -it hermes-gateway gateway setup"
echo ""

# ── Next steps summary ─────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}🚀 Once Setup is Complete, Run This Command:${RESET}"
echo ""
echo "   cd $HERMES_TARGET_REPO_DIRECTORY && docker compose --profile manual up hermes-chat"
echo ""

echo -e "${CYAN}─────────────────────────────────────────────────────────${RESET}"
echo ""
echo -e "${YELLOW}ℹ️  Note:${RESET}"
echo "   The gateway service is NOT yet running. You must first:"
echo "   Run 'docker compose run -it hermes-setup' to configure Hermes"
echo ""
