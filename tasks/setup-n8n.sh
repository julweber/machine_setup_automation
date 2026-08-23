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

# Write .env
step "Creating .env file"
sudo tee "${N8N_DIR}/.env" <<'ENV_EOF' > /dev/null
# n8n environment – edit before first launch!

DOMAIN_NAME=example.com
SUBDOMAIN=n8n
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${SUBDOMAIN}.${DOMAIN_NAME}/
GENERIC_TIMEZONE=Europe/Berlin
SSL_EMAIL=user@example.com
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
ENV_EOF

info ".env written – review values before starting n8n"

# Build n8n service definition
if [[ "${TRAEFIK_ENABLED}" == "true" ]]; then
  info "Traefik enabled – will inject labels"
  N8N_SERVICE=$(cat <<'N8N_TRAEFIK'
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    labels:
      - traefik.enable=true
      - traefik.docker.network=proxy
      - traefik.http.routers.n8n.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)
      - traefik.http.routers.n8n.tls=true
      - traefik.http.routers.n8n.entrypoints=web,websecure
      - traefik.http.routers.n8n.middlewares=n8n@docker
    environment:
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_HOST=${SUBDOMAIN}.${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${SUBDOMAIN}.${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-Europe/Berlin}
      - TZ=${GENERIC_TIMEZONE:-Europe/Berlin}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files

  traefik:
    image: "traefik"
    restart: always
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
N8N_TRAEFIK
)
else
  warn "Traefik disabled – n8n exposed only on localhost:5678"
  N8N_SERVICE=$(cat <<'N8N_LOCAL'
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=http://localhost:5678/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-Europe/Berlin}
      - TZ=${GENERIC_TIMEZONE:-Europe/Berlin}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files
N8N_LOCAL
)
fi

# Write compose file
step "Creating docker-compose.yml"
{
  echo "services:"
  echo "$N8N_SERVICE"
  cat <<'POSTGRES'
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=changeme
      - POSTGRES_DB=n8n
    volumes:
      - pg_data:/var/lib/postgresql/data

volumes:
  n8n_data:
  pg_data:
POSTGRES

  [[ "${TRAEFIK_ENABLED}" == "true" ]] && echo "  traefik_data:"

  echo ""
  echo "networks:"
  echo "  proxy:"
  echo "    external: true"
} | sudo tee "${COMPOSE_FILE}" > /dev/null

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