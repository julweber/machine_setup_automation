#!/usr/bin/env bash
# =============================================================================
# setup-hermes.sh — Install Hermes Agent with Local Terminal Backend
# =============================================================================
#
# Description:
#   Sets up the Hermes Agent environment using the official prebuilt Docker image.
#   Creates a target directory, generates configuration files from templates,
#   and provides convenience scripts for management.
#   
#   Uses LOCAL terminal backend by default - all terminal commands execute inside
#   the same container where the gateway runs (no separate terminal containers).
#
#   Behavior:
#   - Existing configuration detected → update docker image and restart container
#   - New installation → provide setup instructions for the user
#
# Environment Variables (optional):
#   HERMES_TARGET_REPO_DIRECTORY - Directory to set up Hermes (default: /srv/hermes)
#
# Options:
#   --build-only - Only pull the Docker image, don't configure files
#   -h, --help   - Show help and exit
#
# Usage:
#   ./setup-hermes.sh
#   ./setup-hermes.sh --build-only
#   HERMES_TARGET_REPO_DIRECTORY=/opt/hermes ./setup-hermes.sh
# =============================================================================

set -euo pipefail

# Determine script directory and source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LIB_PATH="$(realpath "${SCRIPT_DIR}/../lib/helpers.sh")"

# shellcheck disable=SC1090
source "${LIB_PATH}" || {
  echo "[ERROR] Shared library not found: ${LIB_PATH}" >&2
  exit 1
}

# Configuration
HERMES_TARGET_REPO_DIRECTORY="${HERMES_TARGET_REPO_DIRECTORY:-/srv/hermes}"
HERMES_DATA_DIRECTORY="${HERMES_TARGET_REPO_DIRECTORY}/.hermes"
HERMES_WORKSPACE_DIRECTORY="${HERMES_TARGET_REPO_DIRECTORY}/workspace"
TEMPLATES_DIR="${SCRIPT_DIR}/../templates/hermes"
HERMES_IMAGE="nousresearch/hermes-agent:latest"

# =============================================================================
# USAGE / HELP
# =============================================================================

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [OPTIONS]

Sets up the Hermes Agent environment using the official prebuilt Docker image
(nousresearch/hermes-agent). Creates the target directory, generates
configuration files from templates, and provides convenience scripts.
Uses the LOCAL terminal backend by default.

${BOLD}Options:${RESET}
  --build-only    Only pull the Docker image, don't configure files
  -h, --help      Show this help and exit

${BOLD}Environment variables${RESET} (all optional):
  HERMES_TARGET_REPO_DIRECTORY  Directory to set up Hermes (default: /srv/hermes)
EOF
}

# Parse arguments
BUILD_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --build-only)
      BUILD_ONLY=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $arg (see --help)"
      ;;
  esac
done

# =============================================================================
# Main
# =============================================================================

step "Setting up Hermes Agent (Local Terminal Backend)"

# Check Docker installation
if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Please install Docker first."
fi

if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start Docker and try again."
fi

success "Docker is available"

# Create target directory
step "Setting up target directory: ${HERMES_TARGET_REPO_DIRECTORY}"
if [[ ! -d "${HERMES_TARGET_REPO_DIRECTORY}" ]]; then
  sudo mkdir -p "${HERMES_TARGET_REPO_DIRECTORY}"
  info "Setting ownership to 10000:10000 for directory ${HERMES_TARGET_REPO_DIRECTORY}"
  sudo chown -R 10000:10000 "${HERMES_TARGET_REPO_DIRECTORY}"
  info "Created directory: ${HERMES_TARGET_REPO_DIRECTORY}"
else
  info "Target directory already exists"
fi

# Create data directory
step "Setting up data directory: ${HERMES_DATA_DIRECTORY}"
if [[ ! -d "${HERMES_DATA_DIRECTORY}" ]]; then
  sudo mkdir -p "${HERMES_DATA_DIRECTORY}"
  info "Setting ownership to 10000:10000 for directory ${HERMES_DATA_DIRECTORY}"
  sudo chown -R 10000:10000 "${HERMES_DATA_DIRECTORY}"
  info "Created directory: ${HERMES_DATA_DIRECTORY}"
else
  info "Target data directory already exists"
fi

# Create workspace directory
step "Setting up workspace directory: ${HERMES_WORKSPACE_DIRECTORY}"
if [[ ! -d "${HERMES_WORKSPACE_DIRECTORY}" ]]; then
  sudo mkdir -p "${HERMES_WORKSPACE_DIRECTORY}"
  info "Setting ownership to 10000:10000 for directory ${HERMES_WORKSPACE_DIRECTORY}"
  sudo chown -R 10000:10000 "${HERMES_WORKSPACE_DIRECTORY}"
  info "Created workspace directory: ${HERMES_WORKSPACE_DIRECTORY}"
else
  info "Workspace directory already exists"
fi

# Pull Docker image
step "Pulling Hermes Docker image"
docker pull "${HERMES_IMAGE}"

if [[ "${BUILD_ONLY}" == true ]]; then
  success "Hermes image pulled successfully (--build-only mode)"
  exit 0
fi

# =============================================================================
# Check for existing configuration
# =============================================================================
# Existing config is indicated by: /srv/hermes/.hermes/config.yaml OR .env exists
# (these are mounted into the docker image at /opt/data)
# Note: Using sudo for the check because these files are created by the hermes
# container (uid 10000) and may not be readable by regular users.
# =============================================================================

HERMES_CONFIG_PATH="/srv/hermes/.hermes/config.yaml"
HERMES_ENV_PATH="/srv/hermes/.hermes/.env"

# Use sudo for file existence check to handle permission issues
# (files may only be accessible by root/hermes user)
HERMES_CONFIG_EXISTS=false
HERMES_ENV_EXISTS=false
if sudo test -f "${HERMES_CONFIG_PATH}" 2>/dev/null; then
  HERMES_CONFIG_EXISTS=true
fi
if sudo test -f "${HERMES_ENV_PATH}" 2>/dev/null; then
  HERMES_ENV_EXISTS=true
fi

if [[ "${HERMES_CONFIG_EXISTS}" == true ]] || [[ "${HERMES_ENV_EXISTS}" == true ]]; then
  # ===========================================================================
  # Existing installation - update image and restart container
  # ===========================================================================

  step "Existing Hermes configuration detected"
  info "Found config at: ${HERMES_CONFIG_PATH}"

  # Copy docker-compose.yml if needed
  if [[ -f "${TEMPLATES_DIR}/docker-compose.yml" ]]; then
    if [[ ! -f "${HERMES_TARGET_REPO_DIRECTORY}/docker-compose.yml" ]]; then
      sudo cp "${TEMPLATES_DIR}/docker-compose.yml" "${HERMES_TARGET_REPO_DIRECTORY}/docker-compose.yml"
      info "Copied docker-compose.yml"
    else
      info "docker-compose.yml already exists, keeping existing"
    fi
  fi

  # Restart the gateway container if it exists
  step "Restarting Hermes gateway container"
  if docker ps -a --format '{{.Names}}' | grep -q "^hermes-gateway$"; then
    if docker ps --format '{{.Names}}' | grep -q "^hermes-gateway$"; then
      info "Restarting running container..."
      docker restart hermes-gateway 2>/dev/null || true
    else
      info "Starting existing container..."
      docker start hermes-gateway 2>/dev/null || true
    fi
    success "Hermes gateway container restarted with new image"
  else
    info "Container 'hermes-gateway' not found - starting it"
    if [[ -f "${HERMES_TARGET_REPO_DIRECTORY}/docker-compose.yml" ]]; then
      (cd "${HERMES_TARGET_REPO_DIRECTORY}" && docker compose up -d hermes-gateway 2>/dev/null) || {
        warn "Failed to start via docker compose. Run manually:"
        info "  cd ${HERMES_TARGET_REPO_DIRECTORY} && docker compose up -d hermes-gateway"
      }
    fi
  fi

  # Post-update instructions
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
  success "Hermes Agent updated!"
  echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "${GREEN}Existing configuration found at:${RESET}"
  echo "  ${HERMES_CONFIG_PATH}"
  echo "  ${HERMES_ENV_PATH}"
  echo ""
  echo -e "${YELLOW}🔄 Docker image updated to: ${HERMES_IMAGE}${RESET}"
  echo ""
  echo -e "${YELLOW}📋 Common commands:${RESET}"
  echo ""
  echo "  ${BOLD}View logs:${RESET}"
  echo "    docker logs -f hermes-gateway"
  echo ""
  echo "  ${BOLD}Restart gateway:${RESET}"
  echo "    docker restart hermes-gateway"
  echo ""
  echo "  ${BOLD}Access shell:${RESET}"
  echo "    docker exec -it hermes-gateway bash"
  echo ""
  echo -e "${CYAN}─────────────────────────────────────────────────────────${RESET}"
  exit 0
fi

# ===========================================================================
# New installation - provide setup instructions
# ===========================================================================

step "No existing Hermes configuration found"
info "This is a fresh installation"

# Copy configuration files from templates
step "Copying configuration files from templates"

if [[ -f "${TEMPLATES_DIR}/docker-compose.yml" ]]; then
  sudo cp "${TEMPLATES_DIR}/docker-compose.yml" "${HERMES_TARGET_REPO_DIRECTORY}/docker-compose.yml"
  info "Copied docker-compose.yml (local terminal backend)"
else
  warn "Template not found: ${TEMPLATES_DIR}/docker-compose.yml"
fi

if [[ -f "${TEMPLATES_DIR}/restart_hermes.sh" ]]; then
  sudo cp "${TEMPLATES_DIR}/restart_hermes.sh" "${HERMES_TARGET_REPO_DIRECTORY}/restart_hermes.sh"
  sudo chmod +x "${HERMES_TARGET_REPO_DIRECTORY}/restart_hermes.sh"
  info "Copied restart_hermes.sh"
else
  warn "Template not found: ${TEMPLATES_DIR}/restart_hermes.sh"
fi

# Post-setup instructions
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
success "Hermes Agent setup files prepared!"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

echo -e "${YELLOW}📁 Your files:${RESET}"
echo "   Data directory:     ${HERMES_DATA_DIRECTORY}"
echo "   Workspace directory: ${HERMES_WORKSPACE_DIRECTORY}"
echo "   Docker image:       ${HERMES_IMAGE}"
echo ""

echo -e "${YELLOW}🚀 Step 1: Run the initial setup wizard${RESET}"
echo ""
echo "   cd ${HERMES_TARGET_REPO_DIRECTORY}"
echo "   docker compose run hermes-setup"
echo ""
echo "   This will launch the setup wizard which will:"
echo "   - Ask for your LLM provider API keys"
echo "   - Configure the messaging gateway"
echo "   - Set up your preferences"
echo ""
echo "   Press Ctrl+C when the setup wizard is complete"
echo ""

echo -e "${YELLOW}📝 Step 2: Customize configuration (optional)${RESET}"
echo ""
echo "   The config template is at:"
echo "   ${TEMPLATES_DIR}/config.yaml.example"
echo ""
echo "   You can edit the hermes configuration directly:"
echo "   nano ${HERMES_DATA_DIRECTORY}/config.yaml"
echo ""
echo "   Or use the CLI inside the container:"
echo "   docker compose exec hermes-gateway hermes config edit"
echo ""

echo -e "${YELLOW}💬 Step 3: Start the gateway${RESET}"
echo ""
echo "   cd ${HERMES_TARGET_REPO_DIRECTORY}"
echo "   docker compose up hermes-gateway"
echo ""

echo -e "${YELLOW}📖 Common commands:${RESET}"
echo ""
echo "   ${BOLD}hermes help:${RESET}"
echo "     docker compose exec hermes-gateway hermes --help"
echo ""
echo "   ${BOLD}Gateway management:${RESET}"
echo "     cd ${HERMES_TARGET_REPO_DIRECTORY}"
echo "     ./restart_hermes.sh              # Start/restart gateway"
echo "     docker compose logs -f hermes-gateway  # View logs"
echo ""
echo "   ${BOLD}Interactive session (gateway):${RESET}"
echo "     docker exec -it hermes-gateway bash"
echo "     hermes chat"
echo "   or"
echo "     docker compose run hermes-chat"
echo ""
echo "   ${BOLD}Model selection:${RESET}"
echo "     docker compose exec hermes-gateway hermes model"
echo ""
echo "   ${BOLD}Messaging setup:${RESET}"
echo "     docker compose exec hermes-gateway hermes gateway setup"
echo ""

echo -e "${YELLOW}📋 Example config.yaml options:${RESET}"
echo ""
echo "   Edit ${HERMES_DATA_DIRECTORY}/config.yaml to customize:"
echo ""
echo "   ${BOLD}terminal.backend:${RESET}     Set to 'local' for in-container execution"
echo "   ${BOLD}model.default:${RESET}        Change your preferred AI model"
echo "   ${BOLD}tools.enabled_toolsets:${RESET} Enable/disable tool categories"
echo "   ${BOLD}web.backend:${RESET}          Choose web search backend (exa, tavily, etc.)"
echo ""

echo -e "${CYAN}─────────────────────────────────────────────────────────${RESET}"
echo ""
echo -e "${GREEN}${BOLD}✅ Setup Complete!${RESET}"
echo ""
echo -e "${YELLOW}ℹ️  Next steps:${RESET}"
echo "   1. Run: cd ${HERMES_TARGET_REPO_DIRECTORY} && docker compose run hermes-setup"
echo "   2. After setup, start the gateway: docker compose up hermes-gateway"
echo ""
echo -e "${CYAN}─────────────────────────────────────────────────────────${RESET}"