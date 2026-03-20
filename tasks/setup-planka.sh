#!/usr/bin/env bash
# =============================================================================
# Planka Docker Setup Script
# =============================================================================
#
# DESCRIPTION:
#   Automated setup script for deploying Planka, a self-hosted Kanban board,
#   using Docker Compose. Planka requires PostgreSQL and a generated secret key.
#
# KEY ACTIONS:
#   1. Pre-flight checks: Verifies root access, Docker installation & daemon
#   2. Stops and removes any existing Planka Docker Compose stack (with prompt)
#   3. Creates persistent storage directories on the host system
#   4. Generates a SECRET_KEY via openssl
#   5. Generates a docker-compose.yml based on configuration variables
#   6. Pulls required Docker images (Planka + PostgreSQL)
#   7. Starts the Docker Compose stack in detached mode
#   8. Waits for Planka web UI to become available (max 120s)
#   9. Optionally creates an admin user via the built-in CLI
#  10. Displays access information and useful management commands
#
# IMPORTANT VARIABLES:
#   PLANKA_HOME        - Host directory for persistent data (default: /srv/planka)
#   PLANKA_IMAGE       - Docker image tag to use (default: ghcr.io/plankanban/planka:latest)
#   CONTAINER_NAME     - Docker container name (default: planka)
#   HTTP_PORT          - Host port for web UI (default: 3000)
#   BASE_URL           - Full base URL used by Planka (default: http://localhost:HTTP_PORT)
#   POSTGRES_*         - PostgreSQL credentials
#   SECRET_KEY         - Application secret; auto-generated with openssl if empty
#   ADMIN_EMAIL        - If set, creates an admin user non-interactively (requires ADMIN_PASSWORD)
#   ADMIN_PASSWORD     - Admin password (used only when ADMIN_EMAIL is set)
#   ADMIN_NAME         - Admin display name (default: "Admin")
#   ADMIN_USERNAME     - Admin username (optional)
#
# DEPENDENCIES:
#   - Docker: Must be installed and daemon must be running
#   - Docker Compose: Required for orchestration
#   - Root/sudo access: Required for directory creation and Docker operations
#   - curl: Used for health check polling
#   - openssl: Used to generate SECRET_KEY (if not provided)
#
# OUTPUTS:
#   - ${PLANKA_HOME}/docker-compose.yml - Generated compose configuration
#   - ${PLANKA_HOME}/data/              - Planka application data (uploads etc.)
#   - ${PLANKA_HOME}/postgres/          - PostgreSQL data directory
#
# USAGE:
#   sudo ./setup-planka.sh
#
#   # Or with custom configuration:
#   sudo HTTP_PORT=8080 BASE_URL=http://planka.example.com ./setup-planka.sh
#
#   # With pre-set admin credentials (non-interactive):
#   sudo ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=s3cur3 ./setup-planka.sh
#
# REFERENCE:
#   https://docs.planka.cloud/docs/installation/docker/production-version
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running (or export them)
# ─────────────────────────────────────────────────────────────────────────────

PLANKA_HOME="${PLANKA_HOME:-/srv/planka}"
PLANKA_IMAGE="${PLANKA_IMAGE:-ghcr.io/plankanban/planka:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-planka}"

HTTP_PORT="${HTTP_PORT:-4444}"
BASE_URL="${BASE_URL:-http://localhost:${HTTP_PORT}}"

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
# COLOURS & HELPERS
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}▶ $*${RESET}"; }


# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

step "Running pre-flight checks"

if [[ "$EUID" -ne 0 ]]; then
  error "Please run this script as root or with sudo."
fi

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

mkdir -p "${PLANKA_HOME}/data"
mkdir -p "${PLANKA_HOME}/postgres"

# Planka's Node process runs as UID 1000 — ensure it can write to the data dir
chown -R 1000:1000 "${PLANKA_HOME}/data"

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

cat > "$COMPOSE_FILE" <<EOF
services:
  planka:
    image: ${PLANKA_IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: on-failure
    ports:
      - "${HTTP_PORT}:1337"
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
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    container_name: ${CONTAINER_NAME}-postgres
    restart: on-failure
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
  warn "Planka did not respond within ${MAX_WAIT}s."
  warn "It may still be starting. Check logs with:"
  warn "  docker compose -f ${COMPOSE_FILE} logs -f"
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
echo -e "  ${BOLD}Local port${RESET}       http://localhost:${HTTP_PORT}"
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
echo ""
