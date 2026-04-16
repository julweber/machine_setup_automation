#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-planka.sh — Install Planka Kanban board
# =============================================================================
#
# Description:
#   Deploys Planka, a self-hosted Kanban board, using Docker Compose.
#
# Environment Variables (optional):
#   PLANKA_HOME        - Data directory (default: /srv/planka)
#   HTTP_PORT          - Host port (default: 1337, ignored when PLANKA_TRAEFIK=true)
#   BASE_URL           - Full base URL (default: http://localhost:HTTPPORT or https://PLANKA_DOMAIN)
#   POSTGRES_PASSWORD  - Database password (optional)
#   SECRET_KEY         - App secret (auto-generated if empty)
#   ADMIN_EMAIL        - Create admin user non-interactively
#   ADMIN_PASSWORD     - Admin password
#
#   Traefik reverse-proxy integration (opt-in):
#   PLANKA_TRAEFIK     - Set to "true" to enable Traefik routing (default: false)
#   PLANKA_DOMAIN      - Domain for Traefik access (required when PLANKA_TRAEFIK=true)
#   PROXY_NETWORK      - Traefik's external Docker network name (default: proxy)
#
# Usage:
#   ./setup-planka.sh
#   HTTP_PORT=8080 ./setup-planka.sh
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

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running (or export them)
# ─────────────────────────────────────────────────────────────────────────────

PLANKA_HOME="${PLANKA_HOME:-/srv/planka}"
PLANKA_IMAGE="${PLANKA_IMAGE:-ghcr.io/plankanban/planka:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-planka}"

HTTP_PORT="${HTTP_PORT:-1337}"
BASE_URL="${BASE_URL:-http://localhost:${HTTP_PORT}}"

# Traefik reverse-proxy integration (opt-in)
PLANKA_TRAEFIK="${PLANKA_TRAEFIK:-false}"
PLANKA_DOMAIN="${PLANKA_DOMAIN:-}"
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"

# PostgreSQL settings
POSTGRES_DB="${POSTGRES_DB:-planka}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"          # Leave empty to use trust auth (dev only)

# Application secret key — generated automatically if left empty
SECRET_KEY="${SECRET_KEY:-}"

# Admin user (optional — leave ADMIN_EMAIL empty to be prompted after startup)
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
ADMIN_NAME="${ADMIN_NAME:-Admin}"
ADMIN_USERNAME="${ADMIN_USERNAME:-}"


# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

step "Running pre-flight checks"

# Docker commands don't require root if user is in docker group
if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH. Run setup-docker.sh first."
fi

if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi

if ! command -v openssl &>/dev/null; then
  error "openssl is not installed. Install it with: apt-get install openssl"
fi

success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

# Traefik pre-flight (only when opt-in)
if [[ "$PLANKA_TRAEFIK" == "true" ]]; then
  if ! ensure_proxy_network; then
    error "Traefik proxy network '${PROXY_NETWORK}' not found or inaccessible."
  fi
  if [[ -z "$PLANKA_DOMAIN" ]]; then
    error "PLANKA_DOMAIN must be set when PLANKA_TRAEFIK=true."
  fi
  # Auto-set BASE_URL for Traefik mode
  BASE_URL="https://${PLANKA_DOMAIN}"
fi

# Warn if admin password looks weak
if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" && ${#ADMIN_PASSWORD} -lt 8 ]]; then
  warn "ADMIN_PASSWORD is shorter than 8 characters — consider a stronger password."
  read -rp "    Continue anyway? [y/N] " _ans
  [[ "${_ans,,}" == "y" ]] || exit 0
fi


# ─────────────────────────────────────────────────────────────────────────────
# GENERATE SECRET KEY (if not provided)
# ─────────────────────────────────────────────────────────────────────────────

step "Preparing SECRET_KEY"

if [[ -z "$SECRET_KEY" ]]; then
  SECRET_KEY="$(openssl rand -hex 64)"
  info "Generated new SECRET_KEY."
else
  info "Using provided SECRET_KEY."
fi


# ─────────────────────────────────────────────────────────────────────────────
# STOP & REMOVE EXISTING COMPOSE STACK (if any)
# ─────────────────────────────────────────────────────────────────────────────

step "Checking for an existing Planka compose stack"

COMPOSE_FILE="${PLANKA_HOME}/docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
  warn "Existing docker-compose.yml found at ${COMPOSE_FILE}."
  read -rp "    Tear down existing stack and re-create? Data in ${PLANKA_HOME}/data will be preserved. [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    info "Stopping and removing existing stack..."
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    success "Old stack removed."
  else
    info "Keeping existing stack. Exiting."
    exit 0
  fi
fi


# ─────────────────────────────────────────────────────────────────────────────
# CREATE PERSISTENT HOST DIRECTORIES
# ─────────────────────────────────────────────────────────────────────────────

step "Creating persistent storage directories under ${PLANKA_HOME}"

# Create directories with sudo since /srv requires elevated privileges
sudo mkdir -p "${PLANKA_HOME}/data" "${PLANKA_HOME}/postgres"

# Planka's Node process runs as UID 1000 — ensure it can write to the data dir
# Also make postgres directory writable (PostgreSQL container may need to create files there)
# Change ownership of the entire PLANKA_HOME so we can write docker-compose.yml as regular user
sudo chown -R 1000:1000 "${PLANKA_HOME}" || {
  warn "Could not change ownership of ${PLANKA_HOME}. You may need to run this script with sudo."
}
success "Directories ready."

success "Directories ready."


# ─────────────────────────────────────────────────────────────────────────────
# BUILD DATABASE URL
# ─────────────────────────────────────────────────────────────────────────────

if [[ -n "$POSTGRES_PASSWORD" ]]; then
  DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres/${POSTGRES_DB}"
  PG_AUTH_METHOD="md5"
else
  # Trust auth — no password required (suitable for dev/local setups)
  DATABASE_URL="postgresql://${POSTGRES_USER}@postgres/${POSTGRES_DB}"
  PG_AUTH_METHOD="trust"
fi


# ─────────────────────────────────────────────────────────────────────────────
# GENERATE DOCKER COMPOSE FILE
# ─────────────────────────────────────────────────────────────────────────────

step "Generating ${COMPOSE_FILE}"

# Write docker-compose.yml with sudo since /srv directory is owned by root
cat > "$COMPOSE_FILE" <<EOF
services:
  planka:
    image: ${PLANKA_IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: on-failure
$(if [[ "$PLANKA_TRAEFIK" != "true" ]]; then echo '    ports:'; echo "      - \"${HTTP_PORT}:1337\"  # Local access via http://localhost:${HTTP_PORT}"; fi)
    volumes:
      - ${PLANKA_HOME}/data:/app/data
    environment:
      - BASE_URL=${BASE_URL}
      - DATABASE_URL=${DATABASE_URL}
      - SECRET_KEY=${SECRET_KEY}
      # Uncomment and set to lock down the default admin (prevents edit/delete via UI):
      # - DEFAULT_ADMIN_EMAIL=${ADMIN_EMAIL}
      # Timezone / localisation
      # - DEFAULT_LANGUAGE=en-US
      # Upload / token settings
      # - MAX_UPLOAD_FILE_SIZE=
      # - TOKEN_EXPIRES_IN=365
      # Outgoing proxy / blocked IPs (internal Squid proxy used by default)
      # - OUTGOING_BLOCKED_HOSTS=localhost,postgres
    networks:
      - planka
$(if [[ "$PLANKA_TRAEFIK" == "true" ]]; then echo '    labels:'; echo '      - "traefik.enable=true"'; echo "      - \"traefik.docker.network=\${PROXY_NETWORK}\""; echo '      - "traefik.http.routers.planka.rule=Host(`${PLANKA_DOMAIN}`)"'; echo '      - "traefik.http.routers.planka.entrypoints=websecure"'; echo '      - "traefik.http.routers.planka.tls.certresolver=letsencrypt"'; echo '      - "traefik.http.services.planka.loadbalancer.server.port=1337"'; fi)
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    container_name: ${CONTAINER_NAME}-postgres
    restart: on-failure
    networks:
      - planka
    volumes:
      - ${PLANKA_HOME}/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_HOST_AUTH_METHOD=${PG_AUTH_METHOD}
$(if [[ -n "$POSTGRES_PASSWORD" ]]; then echo "      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"; fi)
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  planka:
    external: false
$(if [[ "$PLANKA_TRAEFIK" == "true" ]]; then echo "  \${PROXY_NETWORK}:"; echo "    external: true"; fi)
EOF

success "docker-compose.yml written to ${COMPOSE_FILE}"


# ─────────────────────────────────────────────────────────────────────────────
# PULL IMAGES
# ─────────────────────────────────────────────────────────────────────────────

step "Pulling Docker images"
docker compose -f "$COMPOSE_FILE" pull
success "Images pulled."


# ─────────────────────────────────────────────────────────────────────────────
# START THE STACK
# ─────────────────────────────────────────────────────────────────────────────

step "Starting Planka stack (detached)"
docker compose -f "$COMPOSE_FILE" up -d
success "Stack started."


# ─────────────────────────────────────────────────────────────────────────────
# WAIT FOR PLANKA TO BECOME AVAILABLE
# ─────────────────────────────────────────────────────────────────────────────

step "Waiting for Planka web UI to respond on port ${HTTP_PORT}"

MAX_WAIT=120
INTERVAL=5
ELAPSED=0
READY=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HTTP_PORT}" || true)
  if echo "$HTTP_CODE" | grep -qE "^(200|302|303)"; then
    READY=true
    break
  fi
  echo -ne "\r    Waited ${ELAPSED}s / ${MAX_WAIT}s (HTTP ${HTTP_CODE}) ..."
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""

if [[ "$READY" == "true" ]]; then
  success "Planka is up and responding!"
else
  if [[ "$PLANKA_TRAEFIK" == "true" ]]; then
    warn "Planka did not respond within ${MAX_WAIT}s."
    warn "It may still be starting, or DNS/TLS may need time to propagate."
    warn "  Check container: docker compose -f ${COMPOSE_FILE} logs -f"
    warn "  Check Traefik:  docker logs traefik | grep ${PLANKA_DOMAIN}"
  else
    warn "Planka did not respond within ${MAX_WAIT}s."
    warn "It may still be starting. Check logs with:"
    warn "  docker compose -f ${COMPOSE_FILE} logs -f"
  fi
fi


# ─────────────────────────────────────────────────────────────────────────────
# CREATE ADMIN USER
# ─────────────────────────────────────────────────────────────────────────────

step "Creating admin user"

if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
  info "Creating admin user non-interactively (${ADMIN_EMAIL})..."
  docker compose -f "$COMPOSE_FILE" run --rm planka \
    npm run db:create-admin-user -- \
      --email "${ADMIN_EMAIL}" \
      --password "${ADMIN_PASSWORD}" \
      --name "${ADMIN_NAME}" \
      ${ADMIN_USERNAME:+--username "${ADMIN_USERNAME}"} \
    && success "Admin user '${ADMIN_EMAIL}' created." \
    || warn "Admin user creation failed — the user may already exist, or Planka is still initialising."
else
  info "No ADMIN_EMAIL/ADMIN_PASSWORD provided — run interactively now:"
  echo ""
  echo -e "  ${BOLD}docker compose -f ${COMPOSE_FILE} run --rm planka npm run db:create-admin-user${RESET}"
  echo ""
  read -rp "    Create admin user interactively now? [Y/n] " _create
  if [[ "${_create,,}" != "n" ]]; then
    docker compose -f "$COMPOSE_FILE" run --rm planka npm run db:create-admin-user \
      && success "Admin user created." \
      || warn "Interactive admin creation exited with an error. You can re-run the command above later."
  else
    info "Skipping admin user creation. Remember to create one before first use."
  fi
fi


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Planka setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Web UI${RESET}           ${BASE_URL}"
if [[ "$PLANKA_TRAEFIK" != "true" ]]; then
  echo -e "  ${BOLD}Local port${RESET}       http://localhost:${HTTP_PORT}"
fi
echo -e "  ${BOLD}Data directory${RESET}   ${PLANKA_HOME}/data"
echo -e "  ${BOLD}DB directory${RESET}     ${PLANKA_HOME}/postgres"
echo -e "  ${BOLD}Compose file${RESET}     ${COMPOSE_FILE}"
echo ""
if [[ -n "$ADMIN_EMAIL" ]]; then
  echo -e "  ${BOLD}Admin email${RESET}      ${ADMIN_EMAIL}"
  echo ""
fi
echo -e "${BOLD}Useful commands:${RESET}"
echo -e "  Follow logs        :  docker compose -f ${COMPOSE_FILE} logs -f"
echo -e "  Stop stack         :  docker compose -f ${COMPOSE_FILE} down"
echo -e "  Start stack        :  docker compose -f ${COMPOSE_FILE} up -d"
echo -e "  Restart stack      :  docker compose -f ${COMPOSE_FILE} restart"
echo -e "  Shell into app     :  docker exec -it ${CONTAINER_NAME} sh"
echo -e "  Create admin user  :  docker compose -f ${COMPOSE_FILE} run --rm planka npm run db:create-admin-user"
if [[ "$PLANKA_TRAEFIK" == "true" ]]; then
  echo ""
  echo -e "${CYAN}  # Traefik-specific debug commands${RESET}"
  echo -e "  Check access logs:  docker logs traefik | grep ${PLANKA_DOMAIN}"
  echo -e "  Verify DNS       :  dig ${PLANKA_DOMAIN}"
fi
echo ""
