#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-nanobot.sh — Install Nanobot
# =============================================================================
#
# Description:
#   Sets up the nanobot environment by cloning the repository, building Docker
#   images, and initializing the nanobot container.
#
# Environment Variables (optional):
#   NANOBOT_TARGET_REPO_DIRECTORY - Clone destination (default: /srv/nanobot)
#
# Usage:
#   ./setup-nanobot.sh
#   NANOBOT_TARGET_REPO_DIRECTORY=/opt/nanobot ./setup-nanobot.sh
#   ./setup-nanobot.sh --help
# =============================================================================

set -euo pipefail

# Determine script directory and source shared library
SCRIPT_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LIB_PATH="$(realpath "${SCRIPT_REPO_DIR}/../lib/helpers.sh")"

# shellcheck disable=SC1090
source "${LIB_PATH}" || {
  echo "[ERROR] Shared library not found: ${LIB_PATH}" >&2
  exit 1
}

# =============================================================================
# USAGE / HELP
# =============================================================================

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [OPTIONS]

Sets up the nanobot environment by cloning the repository (HKUDS/nanobot),
building Docker images, and initializing the nanobot container.

${BOLD}Options:${RESET}
  -h, --help     Show this help and exit
  --migrate      Migrate a legacy nanobot repo from $HOME/nanobot to /srv/nanobot

${BOLD}Environment variables${RESET} (all optional):
  NANOBOT_TARGET_REPO_DIRECTORY  Clone destination (default: /srv/nanobot)

${BOLD}Note:${RESET} A restart_nanobot.sh script (supports --rebuild) is created
in the target directory for managing the container.
EOF
}

# Parse arguments
MIGRATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --migrate)
      MIGRATE=true
      ;;
    *)
      error "Unknown option: $1 (see --help)"
      ;;
  esac
done

# Configuration
: "${NANOBOT_TARGET_REPO_DIRECTORY:=/srv/nanobot}"
NANOBOT_SHARED_DIRECTORY="$HOME/.nanobot"
DOCKERFILE_EXTEND_SRC="${SCRIPT_REPO_DIR}/../templates/nanobot/Dockerfile.extend"

# =============================================================================
# Legacy location detection (previous default: $HOME/nanobot)
# =============================================================================

LEGACY_DIR="$HOME/nanobot"
if [[ "$NANOBOT_TARGET_REPO_DIRECTORY" == "/srv/nanobot" \
   && ! -d "${NANOBOT_TARGET_REPO_DIRECTORY}" \
   && -d "$LEGACY_DIR" \
   && ( -d "${LEGACY_DIR}/.git" || -f "${LEGACY_DIR}/docker-compose.yml" ) ]]; then
  warn "The default clone destination is now /srv/nanobot (previously: ${LEGACY_DIR})."
  warn "Found an existing nanobot repository at ${LEGACY_DIR}."
  if [[ "$MIGRATE" == "true" ]]; then
    step "Migrating ${LEGACY_DIR} to ${NANOBOT_TARGET_REPO_DIRECTORY}"
    sudo mkdir -p "$(dirname "${NANOBOT_TARGET_REPO_DIRECTORY}")"
    # cp -a preserves .git so tag/revision checkout keeps working; legacy dir is left in place.
    sudo cp -a "$LEGACY_DIR" "${NANOBOT_TARGET_REPO_DIRECTORY}"
    success "Copied ${LEGACY_DIR} to ${NANOBOT_TARGET_REPO_DIRECTORY} (git history preserved). The legacy directory was left in place."
    echo ""
    info "Next steps:"
    info "  1. Stop the container running from the old location:"
    info "       docker compose -f ${LEGACY_DIR}/docker-compose.yml down"
    info "  2. Re-run this script to start nanobot from ${NANOBOT_TARGET_REPO_DIRECTORY}."
    info "  3. Once the new location is verified working, remove the legacy directory manually."
    exit 0
  else
    warn "A fresh clone will proceed in ${NANOBOT_TARGET_REPO_DIRECTORY}. Set NANOBOT_TARGET_REPO_DIRECTORY=${LEGACY_DIR} to keep using the legacy location, or re-run with --migrate to copy it to ${NANOBOT_TARGET_REPO_DIRECTORY}."
  fi
fi

# =============================================================================
# Main
# =============================================================================

step "Setting up Nanobot"

# Pre-flight
if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Please install Docker first."
fi

success "Docker is available"

# Clone or update repository
if [[ ! -d "${NANOBOT_TARGET_REPO_DIRECTORY}" ]]; then
  step "Cloning nanobot repository"
  sudo mkdir -p "${NANOBOT_TARGET_REPO_DIRECTORY}"
  sudo chown "${USER}:${USER}" "${NANOBOT_TARGET_REPO_DIRECTORY}"
  git clone https://github.com/HKUDS/nanobot "${NANOBOT_TARGET_REPO_DIRECTORY}"
else
  step "Updating existing nanobot repository"
  git -C "${NANOBOT_TARGET_REPO_DIRECTORY}" fetch --tags
fi

# Checkout latest tag
LATEST_TAG=$(git -C "${NANOBOT_TARGET_REPO_DIRECTORY}" describe --tags \
  "$(git -C "${NANOBOT_TARGET_REPO_DIRECTORY}" rev-list --tags --max-count=1)")
info "Checking out: ${LATEST_TAG}"
git -C "${NANOBOT_TARGET_REPO_DIRECTORY}" checkout "${LATEST_TAG}"

pushd "${NANOBOT_TARGET_REPO_DIRECTORY}"

# Create restart script
step "Creating restart script"
cat > restart_nanobot.sh << 'RESTART_EOF'
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
RESTART_EOF

chmod +x restart_nanobot.sh

# Build images
step "Building nanobot Docker image"
docker build -t nanobot .

# Copy Dockerfile.extend
if [[ ! -f "${DOCKERFILE_EXTEND_SRC}" ]]; then
  error "Dockerfile.extend not found at ${DOCKERFILE_EXTEND_SRC}"
fi
info "Copying Dockerfile.extend"
cp "${DOCKERFILE_EXTEND_SRC}" Dockerfile.extend

step "Building nanobot-extended image"
docker build -f Dockerfile.extend -t nanobot-extended .

# Write docker-compose.override.yml
step "Writing docker-compose.override.yml"
cat > docker-compose.override.yml << 'COMPOSE_EOF'
# Auto-generated by setup-nanobot.sh
services:
  nanobot-gateway:
    image: nanobot-extended
    build: {}
  nanobot-cli:
    image: nanobot-extended
    build: {}
COMPOSE_EOF

# Initialize
step "Initializing nanobot"
docker compose run --rm nanobot-cli onboard

popd

# Summary
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
success "Nanobot setup complete!"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo "Source:     ${NANOBOT_TARGET_REPO_DIRECTORY}"
echo "Config:     ${NANOBOT_SHARED_DIRECTORY}/config.json"
echo ""
echo "Next steps:"
echo "  cd ${NANOBOT_TARGET_REPO_DIRECTORY}"
echo "  ./restart_nanobot.sh"
echo ""
echo "Test:"
echo "  docker compose -f ${NANOBOT_TARGET_REPO_DIRECTORY}/docker-compose.yml run --rm nanobot-cli agent -m 'Hello!'"