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
#   1. Pre-flight checks: Verifies Docker installation & daemon
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
#   - curl: Used for health check polling
#
# OUTPUTS:
#   - ${FORGEJO_HOME}/docker-compose.yml - Generated compose configuration
#   - ${FORGEJO_HOME}/data/               - Forgejo application data
#   - ${FORGEJO_HOME}/postgres/           - PostgreSQL data (if DB_TYPE=postgres)
#
# USAGE:
#   sudo ./setup-forgejo.sh
#   
#   # Or with custom configuration:
#   FORGEJO_HOME=/opt/forgejo HTTP_PORT=3000 sudo ./setup-forgejo.sh
#
#   # Show help:
#   sudo ./setup-forgejo.sh --help
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

# Traefik reverse-proxy integration (opt-in)
FORGEJO_TRAEFIK="${FORGEJO_TRAEFIK:-false}"            # Set to "true" to enable Traefik labels
FORGEJO_DOMAIN="${FORGEJO_DOMAIN:-}"                   # e.g. git.example.com (required when FORGEJO_TRAEFIK=true)
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"                # Traefik's external Docker network name


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
# USAGE / HELP
# ─────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: sudo $0 [OPTIONS]

Deploys Forgejo (lightweight self-hosted Git forge) using Docker Compose.
Supports SQLite for lightweight setups or PostgreSQL for production use,
with optional Traefik reverse-proxy integration.

Options:
  --interactive   Prompt for confirmation on risky conditions
  -h, --help      Show this help and exit

Environment variables (all optional):
  FORGEJO_HOME        Host directory for persistent data (default: /srv/forgejo)
  FORGEJO_IMAGE       Docker image tag (default: codeberg.org/forgejo/forgejo:14)
  CONTAINER_NAME      Docker container name (default: forgejo)
  USER_UID            UID inside container (default: 1000)
  USER_GID            GID inside container (default: 1000)
  HTTP_PORT           Host port for web UI (default: 89)
  SSH_PORT            Host port for Git SSH access (default: 2223)
  DB_TYPE             Database backend: sqlite or postgres (default: sqlite)
  POSTGRES_DB         PostgreSQL database name (default: forgejo)
  POSTGRES_USER       PostgreSQL user (default: forgejo)
  POSTGRES_PASSWORD   PostgreSQL password (default: changeme — change in prod!)
  FORGEJO_TRAEFIK     Set to "true" to enable Traefik labels (default: false)
  FORGEJO_DOMAIN      Domain for Traefik routing (required when FORGEJO_TRAEFIK=true)
  PROXY_NETWORK       Traefik's external Docker network name (default: proxy)
  HOST_IP             Host IP for an extra LAN port binding (default: auto-detected)
EOF
}

# Parse arguments
INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive)
      INTERACTIVE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1 (see --help)"
      ;;
  esac
  shift
done

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

step "Running pre-flight checks"

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH. Run setup-docker.sh first."
fi

if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi

success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

# Traefik pre-flight (only when opt-in)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$FORGEJO_TRAEFIK" == "true" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/helpers.sh"
  ensure_proxy_network
  if [[ -z "$FORGEJO_DOMAIN" ]]; then
    echo -e "${RED}[ERROR]${RESET} FORGEJO_DOMAIN must be set when FORGEJO_TRAEFIK=true." >&2
    exit 1
  fi
fi

# Warn about default passwords
if [[ "$DB_TYPE" != "sqlite" ]]; then
  if [[ "$POSTGRES_PASSWORD" == "changeme" ]]; then
    warn "You are using the default database password 'changeme'."
    warn "Set POSTGRES_PASSWORD before running in production!"
    if [[ "$INTERACTIVE" == "true" ]]; then
      read -rp "    Continue anyway? [y/N] " _ans
      [[ "${_ans,,}" == "y" ]] || exit 0
    else
      error "POSTGRES_PASSWORD is set to the default 'changeme'. Set a strong POSTGRES_PASSWORD and re-run, or re-run with --interactive to confirm manually."
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# STOP & REMOVE EXISTING COMPOSE STACK (if any)
# ─────────────────────────────────────────────────────────────────────────────

step "Checking for an existing Forgejo compose stack"

COMPOSE_FILE="${FORGEJO_HOME}/docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
  warn "Existing docker-compose.yml found at ${COMPOSE_FILE}."
  if [[ "$INTERACTIVE" == "true" ]]; then
    read -rp "    Tear down existing stack and re-create? Data in ${FORGEJO_HOME}/data will be preserved. [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
      info "Stopping and removing existing stack..."
      sudo docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
      success "Old stack removed."
    else
      info "Keeping existing stack. Exiting."
      exit 0
    fi
  else
    error "Existing Forgejo stack detected at ${FORGEJO_HOME}. Re-run with --interactive to tear down and re-create, or remove ${COMPOSE_FILE} manually."
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CREATE PERSISTENT HOST DIRECTORIES
# ─────────────────────────────────────────────────────────────────────────────

step "Creating persistent storage directories under ${FORGEJO_HOME}"

sudo mkdir -p "${FORGEJO_HOME}/data"

if [[ "$DB_TYPE" == "postgres" ]]; then
  sudo mkdir -p "${FORGEJO_HOME}/postgres"
fi

success "Directories ready."

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE DOCKER COMPOSE FILE
# ─────────────────────────────────────────────────────────────────────────────

step "Generating ${COMPOSE_FILE}"

[[ "$DB_TYPE" != "sqlite" && "$DB_TYPE" != "postgres" ]] && \
  error "Unknown DB_TYPE '${DB_TYPE}'. Valid values: sqlite, postgres"

# ── Networks ──────────────────────────────────────────────────────────────────
SECTION_NETWORKS="networks:
  forgejo:
    external: false"
if [[ "$FORGEJO_TRAEFIK" == "true" ]]; then
  SECTION_NETWORKS+="
  ${PROXY_NETWORK}:
    external: true"
fi

# ── Server: extra environment variables (postgres only) ───────────────────────
SECTION_SERVER_DB_ENV=""
if [[ "$DB_TYPE" == "postgres" ]]; then
  SECTION_SERVER_DB_ENV="\
      - FORGEJO__database__DB_TYPE=postgres
      - FORGEJO__database__HOST=db:5432
      - FORGEJO__database__NAME=${POSTGRES_DB}
      - FORGEJO__database__USER=${POSTGRES_USER}
      - FORGEJO__database__PASSWD=${POSTGRES_PASSWORD}"
fi

# ── Server: networks list ─────────────────────────────────────────────────────
SECTION_SERVER_NETWORKS="    networks:
      - forgejo"
if [[ "$FORGEJO_TRAEFIK" == "true" ]]; then
  SECTION_SERVER_NETWORKS+="
      - ${PROXY_NETWORK}"
fi

# ── Server: ports (always expose HTTP and SSH) ────────────────────────────────
SECTION_SERVER_PORTS="    ports:"
# Add port binding for local access
SECTION_SERVER_PORTS+="
      - \"${HTTP_PORT}:3000\"  # Local access via http://localhost:${HTTP_PORT} or http://${HOST_IP:-localhost}:${HTTP_PORT}"
# Get host IP (fallback to localhost if unavailable) and add second binding for network access
FALLBACK_IP=$(ip route | grep default | awk '{print \$2}' 2>/dev/null || echo "")
if [[ -z "${HOST_IP:-}" ]]; then
  HOST_IP="${FALLBACK_IP:-localhost}"
fi
# Only add network binding if we got a valid non-localhost IP
NETWORK_BIND=""
if [[ -n "$HOST_IP" && "$HOST_IP" != "localhost" ]]; then
  NETWORK_BIND="\n      - \"${HOST_IP}${HTTP_PORT}:3000\"  # Network access for your local subnet (replace ${HOST_IP} with actual host IP if needed)"
fi
SECTION_SERVER_PORTS+="${NETWORK_BIND}
      - \"${SSH_PORT}:22\""

# ── Server: Traefik labels ────────────────────────────────────────────────────
SECTION_SERVER_LABELS=""
if [[ "$FORGEJO_TRAEFIK" == "true" ]]; then
  SECTION_SERVER_LABELS=$(cat <<TRAEFIK_LABELS
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=${PROXY_NETWORK}"
      - "traefik.http.routers.forgejo.rule=Host(\`${FORGEJO_DOMAIN}\`)"
      - "traefik.http.routers.forgejo.entrypoints=websecure"
      - "traefik.http.routers.forgejo.tls.certresolver=letsencrypt"
      - "traefik.http.services.forgejo.loadbalancer.server.port=3000"
TRAEFIK_LABELS
  )
fi

# ── Server: depends_on (postgres only) ───────────────────────────────────────
SECTION_SERVER_DEPENDS=""
if [[ "$DB_TYPE" == "postgres" ]]; then
  SECTION_SERVER_DEPENDS="    depends_on:
      - db"
fi

# ── Database service (postgres only) ─────────────────────────────────────────
SECTION_DB_SERVICE=""
if [[ "$DB_TYPE" == "postgres" ]]; then
  SECTION_DB_SERVICE=$(cat <<DB_SERVICE

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
DB_SERVICE
  )
fi

# ── Assemble and write ────────────────────────────────────────────────────────
{
  printf '%s\n\n' "${SECTION_NETWORKS}"
  printf 'services:\n'
  printf '  server:\n'
  printf '    image: %s\n'           "${FORGEJO_IMAGE}"
  printf '    container_name: %s\n'  "${CONTAINER_NAME}"
  printf '    environment:\n'
  printf '      - USER_UID=%s\n'     "${USER_UID}"
  printf '      - USER_GID=%s\n'     "${USER_GID}"
  [[ -n "${SECTION_SERVER_DB_ENV}"   ]] && printf '%s\n' "${SECTION_SERVER_DB_ENV}"
  printf '    restart: always\n'
  printf '%s\n'                       "${SECTION_SERVER_NETWORKS}"
  printf '    volumes:\n'
  printf '      - %s/data:/data\n'   "${FORGEJO_HOME}"
  printf '      - /etc/timezone:/etc/timezone:ro\n'
  printf '      - /etc/localtime:/etc/localtime:ro\n'
  printf '%s\n'                       "${SECTION_SERVER_PORTS}"
  [[ -n "${SECTION_SERVER_LABELS}"   ]] && printf '%s\n' "${SECTION_SERVER_LABELS}"
  [[ -n "${SECTION_SERVER_DEPENDS}"  ]] && printf '%s\n' "${SECTION_SERVER_DEPENDS}"
  [[ -n "${SECTION_DB_SERVICE}"      ]] && printf '%s\n' "${SECTION_DB_SERVICE}"
  : # ensure brace group exits 0 so pipefail does not trigger on empty optional sections
} | sudo tee "$COMPOSE_FILE" > /dev/null

success "docker-compose.yml written to ${COMPOSE_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
# PULL IMAGES
# ─────────────────────────────────────────────────────────────────────────────

step "Pulling Docker images"
sudo docker compose -f "$COMPOSE_FILE" pull
success "Images pulled."

# ─────────────────────────────────────────────────────────────────────────────
# START THE STACK
# ─────────────────────────────────────────────────────────────────────────────

step "Starting Forgejo stack (detached)"
sudo docker compose -f "$COMPOSE_FILE" up -d
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
