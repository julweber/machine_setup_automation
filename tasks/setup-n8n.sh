#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-n8n.sh — Install n8n automation platform
# =============================================================================
#
# Description:
#   Installs n8n with PostgreSQL. Can optionally configure with Traefik labels.
#
# Environment Variables (optional):
#   N8N_DIR           - Installation directory (default: /srv/n8n)
#   TRAEFIK_ENABLED   - Enable Traefik integration (default: false)
#
# Usage:
#   ./setup-n8n.sh
#   TRAEFIK_ENABLED=true ./setup-n8n.sh
#   ./setup-n8n.sh --help
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

# =============================================================================
# USAGE / HELP
# =============================================================================

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [OPTIONS]

Installs n8n (automation platform) with PostgreSQL using Docker Compose.
Can optionally configure Traefik integration.

${BOLD}Options:${RESET}
  -h, --help    Show this help and exit

${BOLD}Environment variables${RESET} (all optional):
  N8N_DIR           Installation directory (default: /srv/n8n)
  TRAEFIK_ENABLED   Enable Traefik integration (default: false)

${BOLD}Note:${RESET} A .env template with placeholder values is written to
${N8N_DIR:-/srv/n8n}/.env — review it before starting n8n.
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1 (see --help)"
      ;;
  esac
done

# Configuration
: "${N8N_DIR:=/srv/n8n}"
: "${TRAEFIK_ENABLED:=false}"
COMPOSE_FILE="${N8N_DIR}/docker-compose.yml"

# =============================================================================
# Main
# =============================================================================

step "Setting up n8n automation platform"

# Pre-flight
if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Run setup-docker.sh first."
fi

# Create workspace
step "Creating workspace at ${N8N_DIR}"
sudo mkdir -p "${N8N_DIR}"
sudo mkdir -p "${N8N_DIR}/local-files"
success "Directories ready."

# Render .env from template (static quoted heredoc → plain cp)
TEMPLATE_DIR="${SCRIPT_DIR}/../templates/n8n"
step "Creating .env file"
sudo cp "${TEMPLATE_DIR}/env.template" "${N8N_DIR}/.env"

info ".env written – review values before starting n8n"

# Render docker-compose.yml from template (static quoted heredocs → plain cp)
step "Creating docker-compose.yml"
if [[ "${TRAEFIK_ENABLED}" == "true" ]]; then
  sudo cp "${TEMPLATE_DIR}/docker-compose.traefik.yml" "${COMPOSE_FILE}"
else
  sudo cp "${TEMPLATE_DIR}/docker-compose.local.yml" "${COMPOSE_FILE}"
fi

success "docker-compose.yml written"

# Traefik network setup
if [[ "${TRAEFIK_ENABLED}" == "true" ]]; then
  if ! docker network inspect proxy >/dev/null 2>&1; then
    info "Creating 'proxy' Docker network"
    docker network create proxy || true
  fi
fi

# Bring stack up
step "Starting n8n"
docker compose -f "${COMPOSE_FILE}" up -d --build n8n

success "n8n installed successfully"
info "Access at http://localhost:5678 (or https://automation.example.com with Traefik)"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "- Edit ${N8N_DIR}/.env to configure domain/password"
echo "- View logs: docker compose -f ${COMPOSE_FILE} logs -f"