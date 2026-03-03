#!/usr/bin/env bash
# =============================================================================
# Forgejo Docker Setup Script
# =============================================================================
#
# DESCRIPTION:
#   Automated setup script for deploying Forgejo, a lightweight self-hosted
#   Git forge (similar to GitHub/GitLab), using Docker Compose. Supports
#   SQLite for lightweight setups or PostgreSQL for production use.
#
# KEY ACTIONS:
#   1. Pre-flight checks: Verifies root access, Docker installation & daemon
#   2. Stops and removes any existing Forgejo Docker Compose stack (with prompt)
#   3. Creates persistent storage directories on the host system
#   4. Generates a docker-compose.yml file based on DB_TYPE configuration
#   5. Pulls required Docker images (Forgejo + optional PostgreSQL)
#   6. Starts the Docker Compose stack in detached mode
#   7. Waits for Forgejo web UI to become available (max 120s)
#   8. Displays access information and useful management commands
#
# IMPORTANT VARIABLES:
#   FORGEJO_HOME       - Host directory for persistent data (default: /srv/forgejo)
#   FORGEJO_IMAGE      - Docker image tag to use (default: codeberg.org/forgejo/forgejo:14)
#   CONTAINER_NAME     - Docker container name (default: forgejo)
#   HTTP_PORT          - Host port for web UI (default: 89)
#   SSH_PORT           - Host port for Git SSH access (default: 2223)
#   DB_TYPE            - Database backend: "sqlite" or "postgres" (default: sqlite)
#   POSTGRES_*         - PostgreSQL credentials (only used when DB_TYPE=postgres)
#
# DEPENDENCIES:
#   - Docker: Must be installed and daemon must be running
#   - Docker Compose: Required for orchestration
#   - Root/sudo access: Required for directory creation and Docker operations
#   - curl: Used for health check polling
#
# OUTPUTS:
#   - ${FORGEJO_HOME}/docker-compose.yml - Generated compose configuration
#   - ${FORGEJO_HOME}/data/               - Forgejo application data
#   - ${FORGEJO_HOME}/postgres/           - PostgreSQL data (if DB_TYPE=postgres)
#
# USAGE:
#   sudo ./setup_forgejo.sh
#   
#   # Or with custom configuration:
#   sudo FORGEJO_HOME=/opt/forgejo HTTP_PORT=3000 ./setup_forgejo.sh
#
# REFERENCE:
#   https://forgejo.org/docs/latest/admin/installation/docker/
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running
# ─────────────────────────────────────────────────────────────────────────────

FORGEJO_HOME="${FORGEJO_HOME:-/srv/forgejo}"          # Host directory for persistent data
FORGEJO_IMAGE="${FORGEJO_IMAGE:-codeberg.org/forgejo/forgejo:14}"  # Docker image to use
CONTAINER_NAME="${CONTAINER_NAME:-forgejo}"

# User/group IDs the Forgejo process runs as inside the container
USER_UID="${USER_UID:-1000}"
USER_GID="${USER_GID:-1000}"

# Ports mapped on the HOST machine
HTTP_PORT="${HTTP_PORT:-89}"    # Forgejo web UI
SSH_PORT="${SSH_PORT:-2223}"       # Forgejo SSH clone port (avoids conflict with host SSH)

# Database backend: "sqlite", "postgres", or "mysql"
DB_TYPE="${DB_TYPE:-sqlite}"

# PostgreSQL settings (only used when DB_TYPE=postgres)
POSTGRES_DB="${POSTGRES_DB:-forgejo}"
POSTGRES_USER="${POSTGRES_USER:-forgejo}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-changeme}"     # ← change before running!


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
  error "Docker is not installed or not in PATH. Run setup_docker.sh first."
fi

if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi

success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

# Warn about default passwords
if [[ "$DB_TYPE" != "sqlite" ]]; then
  if [[ "$POSTGRES_PASSWORD" == "changeme" ]]; then
    warn "You are using the default database password 'changeme'."
    warn "Set POSTGRES_PASSWORD before running in production!"
    read -rp "    Continue anyway? [y/N] " _ans
    [[ "${_ans,,}" == "y" ]] || exit 0
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# STOP & REMOVE EXISTING COMPOSE STACK (if any)
# ─────────────────────────────────────────────────────────────────────────────

step "Checking for an existing Forgejo compose stack"

COMPOSE_FILE="${FORGEJO_HOME}/docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
  warn "Existing docker-compose.yml found at ${COMPOSE_FILE}."
  read -rp "    Tear down existing stack and re-create? Data in ${FORGEJO_HOME}/data will be preserved. [y/N] " answer
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

step "Creating persistent storage directories under ${FORGEJO_HOME}"

mkdir -p "${FORGEJO_HOME}/data"

if [[ "$DB_TYPE" == "postgres" ]]; then
  mkdir -p "${FORGEJO_HOME}/postgres"
fi

success "Directories ready."

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE DOCKER COMPOSE FILE
# ─────────────────────────────────────────────────────────────────────────────

step "Generating ${COMPOSE_FILE}"

# ── SQLite (no external database) ────────────────────────────────────────────
if [[ "$DB_TYPE" == "sqlite" ]]; then

cat > "$COMPOSE_FILE" <<EOF
networks:
  forgejo:
    external: false

services:
  server:
    image: ${FORGEJO_IMAGE}
    container_name: ${CONTAINER_NAME}
    environment:
      - USER_UID=${USER_UID}
      - USER_GID=${USER_GID}
    restart: always
    networks:
      - forgejo
    volumes:
      - ${FORGEJO_HOME}/data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "${HTTP_PORT}:3000"
      - "${SSH_PORT}:22"
EOF

# ── PostgreSQL ────────────────────────────────────────────────────────────────
elif [[ "$DB_TYPE" == "postgres" ]]; then

cat > "$COMPOSE_FILE" <<EOF
networks:
  forgejo:
    external: false

services:
  server:
    image: ${FORGEJO_IMAGE}
    container_name: ${CONTAINER_NAME}
    environment:
      - USER_UID=${USER_UID}
      - USER_GID=${USER_GID}
      - FORGEJO__database__DB_TYPE=postgres
      - FORGEJO__database__HOST=db:5432
      - FORGEJO__database__NAME=${POSTGRES_DB}
      - FORGEJO__database__USER=${POSTGRES_USER}
      - FORGEJO__database__PASSWD=${POSTGRES_PASSWORD}
    restart: always
    networks:
      - forgejo
    volumes:
      - ${FORGEJO_HOME}/data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "${HTTP_PORT}:3000"
      - "${SSH_PORT}:22"
    depends_on:
      - db

  db:
    image: postgres:14
    container_name: ${CONTAINER_NAME}-db
    restart: always
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    networks:
      - forgejo
    volumes:
      - ${FORGEJO_HOME}/postgres:/var/lib/postgresql/data
EOF

else
  error "Unknown DB_TYPE '${DB_TYPE}'. Valid values: sqlite, postgres"
fi

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

step "Starting Forgejo stack (detached)"
docker compose -f "$COMPOSE_FILE" up -d
success "Stack started."

# ─────────────────────────────────────────────────────────────────────────────
# WAIT FOR FORGEJO TO BECOME AVAILABLE
# ─────────────────────────────────────────────────────────────────────────────

step "Waiting for Forgejo web UI to respond on port ${HTTP_PORT}"

MAX_WAIT=120
INTERVAL=5
ELAPSED=0
READY=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HTTP_PORT}" | grep -qE "^(200|302|303)"; then
    READY=true
    break
  fi
  echo -ne "\r    Waited ${ELAPSED}s / ${MAX_WAIT}s ..."
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""

if [[ "$READY" == "true" ]]; then
  success "Forgejo is up and responding!"
else
  warn "Forgejo did not respond within ${MAX_WAIT}s."
  warn "It may still be starting. Check logs with:"
  warn "  docker compose -f ${COMPOSE_FILE} logs -f"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Forgejo setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Web UI${RESET}           http://localhost:${HTTP_PORT}"
echo -e "  ${BOLD}SSH clone port${RESET}   ${SSH_PORT}  (git clone ssh://git@HOST:${SSH_PORT}/user/repo.git)"
echo -e "  ${BOLD}Database${RESET}         ${DB_TYPE}"
echo -e "  ${BOLD}Data directory${RESET}   ${FORGEJO_HOME}/data"
echo -e "  ${BOLD}Compose file${RESET}     ${COMPOSE_FILE}"
echo ""
echo -e "${YELLOW}  First-time setup:${RESET}"
echo -e "  Open the Web UI and complete the installation wizard."
echo -e "  You will be able to set the admin username and password there."
echo ""
echo -e "${BOLD}Useful commands:${RESET}"
echo -e "  Follow logs    :  docker compose -f ${COMPOSE_FILE} logs -f"
echo -e "  Stop stack     :  docker compose -f ${COMPOSE_FILE} down"
echo -e "  Start stack    :  docker compose -f ${COMPOSE_FILE} up -d"
echo -e "  Restart stack  :  docker compose -f ${COMPOSE_FILE} restart"
echo -e "  Shell into app :  docker exec -it ${CONTAINER_NAME} bash"
echo ""
