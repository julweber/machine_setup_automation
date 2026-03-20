#!/usr/bin/env bash
# shellcheck disable=SC2086,SC1091
# =============================================================================
# Nextcloud Docker Setup Script
# =============================================================================
#
# DESCRIPTION:
#   Automated setup script for deploying Nextcloud, a self-hosted file sync
#   and collaboration platform, using Docker Compose.
#   Supports MariaDB (default), PostgreSQL, or SQLite as the database backend,
#   with optional Redis caching and Traefik reverse-proxy integration.
#
# KEY ACTIONS:
#   1. Pre-flight checks: Verifies Docker installation & daemon
#   2. Stops and removes any existing Nextcloud Docker Compose stack (with prompt)
#   3. Creates persistent storage directories on the host system
#   4. Writes secrets (.env file, chmod 600) — never stored in compose config
#   5. Generates a docker-compose.yml based on DB_TYPE / REDIS / Traefik config
#   6. Pulls required Docker images
#   7. Starts the Docker Compose stack in detached mode
#   8. Waits for the Nextcloud web UI to become available (max 180s)
#   9. Displays access information and useful management commands
#
# IMPORTANT VARIABLES:
#   NEXTCLOUD_HOME          - Host directory for persistent data (default: /srv/nextcloud)
#   NEXTCLOUD_IMAGE         - Docker image tag to use  (default: nextcloud:stable)
#   CONTAINER_NAME          - App container name       (default: nextcloud)
#   HTTP_PORT               - Host port for web UI     (default: 8080)
#   DB_TYPE                 - Database backend: "mariadb" | "postgres" | "sqlite"
#                             (default: mariadb)
#   MYSQL_DATABASE          - MariaDB/MySQL database name   (default: nextcloud)
#   MYSQL_USER              - MariaDB/MySQL user             (default: nextcloud)
#   MYSQL_PASSWORD          - MariaDB/MySQL password         (auto-generated if unset)
#   POSTGRES_DB             - PostgreSQL database name       (default: nextcloud)
#   POSTGRES_USER           - PostgreSQL user                (default: nextcloud)
#   POSTGRES_PASSWORD       - PostgreSQL password            (auto-generated if unset)
#   NEXTCLOUD_ADMIN_USER    - Initial admin username         (default: admin)
#   NEXTCLOUD_ADMIN_PASSWORD- Initial admin password         (auto-generated if unset)
#   REDIS_ENABLED           - Enable Redis caching           (default: true)
#
#   Traefik reverse-proxy integration (opt-in):
#   NEXTCLOUD_TRAEFIK       - Set to "true" to enable Traefik labels (default: false)
#   NEXTCLOUD_DOMAIN        - Domain for Traefik access (required when Traefik=true)
#   PROXY_NETWORK           - Traefik's external Docker network name (default: proxy)
#
# DEPENDENCIES:
#   - Docker: Must be installed and daemon must be running
#   - Docker Compose v2+
#   - curl: Used for health check polling
#   - Traefik instance with proxy network (when NEXTCLOUD_TRAEFIK=true)
#
# OUTPUTS:
#   - ${NEXTCLOUD_HOME}/docker-compose.yml  - Generated compose configuration
#   - ${NEXTCLOUD_HOME}/.env                - Secrets / credentials (mode 600)
#   - ${NEXTCLOUD_HOME}/html/               - Nextcloud web root (persistent)
#   - ${NEXTCLOUD_HOME}/data/               - User data directory (persistent)
#   - ${NEXTCLOUD_HOME}/db/                 - Database data (persistent, if not SQLite)
#
# USAGE:
#   ./setup-nextcloud.sh
#
#   # Custom port and admin credentials:
#   HTTP_PORT=9090 NEXTCLOUD_ADMIN_USER=myadmin NEXTCLOUD_ADMIN_PASSWORD=secret \
#     ./setup-nextcloud.sh
#
#   # With Traefik:
#   NEXTCLOUD_TRAEFIK=true NEXTCLOUD_DOMAIN=cloud.example.com \
#     ./setup-nextcloud.sh
#
#   # PostgreSQL backend:
#   DB_TYPE=postgres POSTGRES_PASSWORD=secret ./setup-nextcloud.sh
#
# REFERENCE:
#   https://hub.docker.com/_/nextcloud
#   https://github.com/nextcloud/docker
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP TRAP — handles partial failures
# ─────────────────────────────────────────────────────────────────────────────

cleanup_on_failure() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo ""
    warn "Setup failed (exit code: ${exit_code})! Cleaning up..."
    if [[ -f "${NEXTCLOUD_HOME}/docker-compose.yml" ]]; then
      sudo docker compose -f "${NEXTCLOUD_HOME}/docker-compose.yml" down --remove-orphans 2>/dev/null || true
      info "Removed partially created stack."
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running
# ─────────────────────────────────────────────────────────────────────────────

# Generate a cryptographically random 24-char alphanumeric password.
# Only called when the corresponding env variable is unset/empty.
_gen_password() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24; echo; }

NEXTCLOUD_HOME="${NEXTCLOUD_HOME:-/srv/nextcloud}"          # Host directory for persistent data
NEXTCLOUD_IMAGE="${NEXTCLOUD_IMAGE:-nextcloud:stable}"      # Docker image to use
CONTAINER_NAME="${CONTAINER_NAME:-nextcloud}"

HTTP_PORT="${HTTP_PORT:-8080}"    # Host port for Nextcloud web UI

# Database backend: "mariadb" (default), "postgres", or "sqlite"
DB_TYPE="${DB_TYPE:-mariadb}"

# MariaDB credentials (used when DB_TYPE=mariadb)
MYSQL_DATABASE="${MYSQL_DATABASE:-nextcloud}"
MYSQL_USER="${MYSQL_USER:-nextcloud}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(_gen_password)}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(_gen_password)}"

# PostgreSQL credentials (used when DB_TYPE=postgres)
POSTGRES_DB="${POSTGRES_DB:-nextcloud}"
POSTGRES_USER="${POSTGRES_USER:-nextcloud}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(_gen_password)}"

# Nextcloud admin account (auto-configured on first run)
NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
NEXTCLOUD_ADMIN_PASSWORD="${NEXTCLOUD_ADMIN_PASSWORD:-$(_gen_password)}"

# Redis caching (strongly recommended)
REDIS_ENABLED="${REDIS_ENABLED:-true}"

# Traefik reverse-proxy integration (opt-in)
NEXTCLOUD_TRAEFIK="${NEXTCLOUD_TRAEFIK:-false}"     # Set to "true" to enable Traefik labels
NEXTCLOUD_DOMAIN="${NEXTCLOUD_DOMAIN:-}"            # e.g. cloud.example.com (required when Traefik=true)
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"             # Traefik's external Docker network name

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

# Register cleanup trap now that all helper functions are defined
trap cleanup_on_failure EXIT

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

step "Running pre-flight checks"

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH. Run setup-docker.sh first."
fi

if ! sudo docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi

success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

# Check Docker Compose v2+
COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "0.0.0")
COMPOSE_MAJOR=$(echo "$COMPOSE_VERSION" | cut -d'.' -f1)
if [[ "$COMPOSE_MAJOR" -lt 2 ]]; then
  warn "Docker Compose v2+ recommended. Current version: ${COMPOSE_VERSION}"
fi

# Validate DB_TYPE
case "$DB_TYPE" in
  mariadb|postgres|sqlite) ;;
  *) error "Unknown DB_TYPE '${DB_TYPE}'. Valid values: mariadb, postgres, sqlite" ;;
esac

# Traefik pre-flight (only when opt-in)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$NEXTCLOUD_TRAEFIK" == "true" ]]; then
  source "${SCRIPT_DIR}/../lib/helpers.sh"
  if ! ensure_proxy_network; then
    error "Traefik proxy network '${PROXY_NETWORK}' not found or inaccessible."
  fi
  if [[ -z "$NEXTCLOUD_DOMAIN" ]]; then
    error "NEXTCLOUD_DOMAIN must be set when NEXTCLOUD_TRAEFIK=true."
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# STOP & REMOVE EXISTING COMPOSE STACK (if any)
# ─────────────────────────────────────────────────────────────────────────────

step "Checking for an existing Nextcloud compose stack"

COMPOSE_FILE="${NEXTCLOUD_HOME}/docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
  warn "Existing docker-compose.yml found at ${COMPOSE_FILE}."
  echo ""
  info "${BOLD}IMPORTANT:${RESET} Your Nextcloud data in ${NEXTCLOUD_HOME}/html and ${NEXTCLOUD_HOME}/data"
  info "will be PRESERVED. Only the running stack will be replaced."
  read -rp "    Tear down existing stack and re-create? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    info "Stopping and removing existing stack..."
    sudo docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    success "Old stack removed."
  else
    info "Keeping existing stack. Exiting."
    exit 0
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CREATE PERSISTENT HOST DIRECTORIES
# ─────────────────────────────────────────────────────────────────────────────

step "Creating persistent storage directories under ${NEXTCLOUD_HOME}"

sudo mkdir -p "${NEXTCLOUD_HOME}/html"   # Nextcloud web root (config, apps, themes)
sudo mkdir -p "${NEXTCLOUD_HOME}/data"   # User files

if [[ "$DB_TYPE" == "mariadb" ]]; then
  sudo mkdir -p "${NEXTCLOUD_HOME}/db"
elif [[ "$DB_TYPE" == "postgres" ]]; then
  sudo mkdir -p "${NEXTCLOUD_HOME}/db"
fi

success "Directories ready."

# ─────────────────────────────────────────────────────────────────────────────
# WRITE SECRETS TO .env (mode 600)
# ─────────────────────────────────────────────────────────────────────────────

step "Writing secrets to ${NEXTCLOUD_HOME}/.env"

ENV_FILE="${NEXTCLOUD_HOME}/.env"

if [[ -f "$ENV_FILE" ]]; then
  warn "Existing .env file found. Backing up to ${ENV_FILE}.bak"
  sudo install -m 600 "$ENV_FILE" "${ENV_FILE}.bak"
fi

# Create with mode 600 from the start — no world-readable window
sudo install -m 600 /dev/null "$ENV_FILE"

# Write credentials with printf so special characters in values are never
# interpreted by the shell (heredocs with << EOF would expand $, `, etc.)
{
  printf '# Nextcloud Environment — KEEP THIS FILE SECURE (mode 600)\n'
  printf '# Generated: %s\n\n' "$(date -Iseconds)"
  printf 'NEXTCLOUD_ADMIN_USER=%s\n' "${NEXTCLOUD_ADMIN_USER}"
  printf 'NEXTCLOUD_ADMIN_PASSWORD=%s\n' "${NEXTCLOUD_ADMIN_PASSWORD}"
} | sudo tee -a "$ENV_FILE" > /dev/null

if [[ "$DB_TYPE" == "mariadb" ]]; then
  {
    printf 'MYSQL_ROOT_PASSWORD=%s\n' "${MYSQL_ROOT_PASSWORD}"
    printf 'MYSQL_DATABASE=%s\n'      "${MYSQL_DATABASE}"
    printf 'MYSQL_USER=%s\n'          "${MYSQL_USER}"
    printf 'MYSQL_PASSWORD=%s\n'      "${MYSQL_PASSWORD}"
  } | sudo tee -a "$ENV_FILE" > /dev/null
elif [[ "$DB_TYPE" == "postgres" ]]; then
  {
    printf 'POSTGRES_DB=%s\n'       "${POSTGRES_DB}"
    printf 'POSTGRES_USER=%s\n'     "${POSTGRES_USER}"
    printf 'POSTGRES_PASSWORD=%s\n' "${POSTGRES_PASSWORD}"
  } | sudo tee -a "$ENV_FILE" > /dev/null
fi

success "Secrets stored in ${ENV_FILE} (mode: 600)."

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE DOCKER COMPOSE FILE
# ─────────────────────────────────────────────────────────────────────────────

step "Generating ${COMPOSE_FILE}"

# ── Header & networks ─────────────────────────────────────────────────────────
cat << EOF | sudo tee "$COMPOSE_FILE" > /dev/null
# Nextcloud Docker Compose Configuration
# Generated: $(date -Iseconds)
# Secrets are loaded from .env (see ${ENV_FILE})

networks:
  nextcloud:
    external: false
EOF

if [[ "$NEXTCLOUD_TRAEFIK" == "true" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
  ${PROXY_NETWORK}:
    external: true
EOF
fi

cat << 'EOF' | sudo tee -a "$COMPOSE_FILE" > /dev/null

services:
EOF

# ── MariaDB service ────────────────────────────────────────────────────────────
if [[ "$DB_TYPE" == "mariadb" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
  db:
    image: mariadb:lts
    container_name: ${CONTAINER_NAME}-db
    restart: always
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    networks:
      - nextcloud
    volumes:
      - ${NEXTCLOUD_HOME}/db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=\${MYSQL_DATABASE}
      - MYSQL_USER=\${MYSQL_USER}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

EOF
fi

# ── PostgreSQL service ────────────────────────────────────────────────────────
if [[ "$DB_TYPE" == "postgres" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
  db:
    image: postgres:16-alpine
    container_name: ${CONTAINER_NAME}-db
    restart: always
    networks:
      - nextcloud
    volumes:
      - ${NEXTCLOUD_HOME}/db:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=\${POSTGRES_DB}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

EOF
fi

# ── Redis service ─────────────────────────────────────────────────────────────
if [[ "$REDIS_ENABLED" == "true" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
  redis:
    image: redis:alpine
    container_name: ${CONTAINER_NAME}-redis
    restart: always
    networks:
      - nextcloud
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

EOF
fi

# ── Nextcloud app service ─────────────────────────────────────────────────────
cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
  app:
    image: ${NEXTCLOUD_IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: always
EOF

# depends_on — use an array so we never get a leading blank line in the YAML
DEPENDS_LIST=()
[[ "$DB_TYPE"       != "sqlite" ]] && DEPENDS_LIST+=("      - db")
[[ "$REDIS_ENABLED" == "true"   ]] && DEPENDS_LIST+=("      - redis")

if [[ ${#DEPENDS_LIST[@]} -gt 0 ]]; then
  printf '    depends_on:\n' | sudo tee -a "$COMPOSE_FILE" > /dev/null
  printf '%s\n' "${DEPENDS_LIST[@]}" | sudo tee -a "$COMPOSE_FILE" > /dev/null
fi

# Ports (direct mode only)
if [[ "$NEXTCLOUD_TRAEFIK" != "true" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
    ports:
      - "${HTTP_PORT}:80"
EOF
fi

# Environment variables
cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
    environment:
      # Admin account (auto-configured on first run)
      - NEXTCLOUD_ADMIN_USER=\${NEXTCLOUD_ADMIN_USER}
      - NEXTCLOUD_ADMIN_PASSWORD=\${NEXTCLOUD_ADMIN_PASSWORD}
      # User data directory inside the container
      - NEXTCLOUD_DATA_DIR=/var/www/html/data
EOF

# DB-specific env vars
if [[ "$DB_TYPE" == "mariadb" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
      # MariaDB connection
      - MYSQL_HOST=db
      - MYSQL_DATABASE=\${MYSQL_DATABASE}
      - MYSQL_USER=\${MYSQL_USER}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
EOF
elif [[ "$DB_TYPE" == "postgres" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
      # PostgreSQL connection
      - POSTGRES_HOST=db
      - POSTGRES_DB=\${POSTGRES_DB}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
EOF
fi

# Redis env vars
if [[ "$REDIS_ENABLED" == "true" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
      # Redis caching
      - REDIS_HOST=redis
      - REDIS_HOST_PORT=6379
EOF
fi

# Traefik-specific env vars (override proxy detection inside Nextcloud/Apache)
if [[ "$NEXTCLOUD_TRAEFIK" == "true" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
      # Reverse-proxy settings (required when behind Traefik)
      - APACHE_DISABLE_REWRITE_IP=1
      - TRUSTED_PROXIES=172.16.0.0/12
      - OVERWRITEPROTOCOL=https
      - OVERWRITECLIURL=https://${NEXTCLOUD_DOMAIN}
      - NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_DOMAIN}
EOF
fi

# Traefik labels
if [[ "$NEXTCLOUD_TRAEFIK" == "true" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=${PROXY_NETWORK}"
      - "traefik.http.routers.nextcloud.rule=Host(\`${NEXTCLOUD_DOMAIN}\`)"
      - "traefik.http.routers.nextcloud.entrypoints=websecure"
      - "traefik.http.routers.nextcloud.tls.certresolver=letsencrypt"
      - "traefik.http.services.nextcloud.loadbalancer.server.port=80"
      # Redirect .well-known CalDAV / CardDAV paths
      - "traefik.http.middlewares.nextcloud-wellknown.redirectregex.regex=^https://(.*)/.well-known/(card|cal)dav"
      - "traefik.http.middlewares.nextcloud-wellknown.redirectregex.replacement=https://\$\${1}/remote.php/dav/"
      - "traefik.http.middlewares.nextcloud-wellknown.redirectregex.permanent=true"
      - "traefik.http.routers.nextcloud.middlewares=nextcloud-wellknown"
EOF
fi

# Networks for app container
cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
    networks:
      - nextcloud
EOF
if [[ "$NEXTCLOUD_TRAEFIK" == "true" ]]; then
  cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
      - ${PROXY_NETWORK}
EOF
fi

# Volumes for app container
cat << EOF | sudo tee -a "$COMPOSE_FILE" > /dev/null
    volumes:
      - ${NEXTCLOUD_HOME}/html:/var/www/html
      - ${NEXTCLOUD_HOME}/data:/var/www/html/data
      - /etc/localtime:/etc/localtime:ro
EOF

success "docker-compose.yml written to ${COMPOSE_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
# PULL IMAGES
# ─────────────────────────────────────────────────────────────────────────────

step "Pulling Docker images"
sudo docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
success "Images pulled."

# ─────────────────────────────────────────────────────────────────────────────
# START THE STACK
# ─────────────────────────────────────────────────────────────────────────────

step "Starting Nextcloud stack (detached)"
sudo docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
success "Stack started."

# ─────────────────────────────────────────────────────────────────────────────
# WAIT FOR NEXTCLOUD TO BECOME AVAILABLE
# ─────────────────────────────────────────────────────────────────────────────

step "Waiting for Nextcloud to respond"

MAX_WAIT=180
INTERVAL=5
ELAPSED=0
READY=false

if [[ "$NEXTCLOUD_TRAEFIK" == "true" ]]; then
  info "Traefik mode: skipping direct health check (TLS access at https://${NEXTCLOUD_DOMAIN})"
  info "Container will be accessible once DNS resolves and TLS is provisioned."
  READY=true
else
  ACCESS_URL="http://localhost:${HTTP_PORT}"
  info "Polling ${ACCESS_URL} (max ${MAX_WAIT}s)..."

  while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ACCESS_URL" 2>/dev/null || echo "000")
    if echo "$HTTP_STATUS" | grep -qE "^(200|302|303)"; then
      READY=true
      break
    fi
    echo -ne "\r    Waited ${ELAPSED}s / ${MAX_WAIT}s (last status: ${HTTP_STATUS}) ..."
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  echo ""
fi

if [[ "$READY" == "true" ]]; then
  success "Nextcloud is up and responding!"
else
  warn "Nextcloud did not respond within ${MAX_WAIT}s."
  warn "It may still be initialising (first-run DB setup can be slow)."
  warn "Check logs with:  sudo docker compose -f ${COMPOSE_FILE} logs -f app"
fi

# Disable cleanup trap on successful completion
trap - EXIT

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Nextcloud setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

if [[ "$NEXTCLOUD_TRAEFIK" == "true" ]]; then
  echo -e "  ${BOLD}Web UI (Traefik)${RESET}   https://${NEXTCLOUD_DOMAIN}"
  echo -e "  ${BOLD}TLS${RESET}                Enabled via Let's Encrypt"
else
  echo -e "  ${BOLD}Web UI${RESET}             http://localhost:${HTTP_PORT}"
fi

echo ""
echo -e "  ${BOLD}Admin user${RESET}         ${NEXTCLOUD_ADMIN_USER}"
echo -e "  ${BOLD}Database${RESET}           ${DB_TYPE}"
echo -e "  ${BOLD}Redis cache${RESET}        ${REDIS_ENABLED}"
echo -e "  ${BOLD}Web root${RESET}           ${NEXTCLOUD_HOME}/html"
echo -e "  ${BOLD}User data${RESET}          ${NEXTCLOUD_HOME}/data"
echo -e "  ${BOLD}Compose file${RESET}       ${COMPOSE_FILE}"
echo -e "  ${BOLD}Secrets file${RESET}       ${ENV_FILE}"
echo ""
echo -e "${YELLOW}  First-time setup:${RESET}"
echo -e "  Nextcloud is auto-configured via environment variables."
echo -e "  Log in with admin user '${NEXTCLOUD_ADMIN_USER}' — password stored in ${ENV_FILE}."
echo -e "  To view it:  sudo grep NEXTCLOUD_ADMIN_PASSWORD ${ENV_FILE}"
echo ""
echo -e "${BOLD}Useful commands:${RESET}"
echo -e "  Follow logs   :  sudo docker compose -f ${COMPOSE_FILE} logs -f"
echo -e "  App logs only :  sudo docker compose -f ${COMPOSE_FILE} logs -f app"
echo -e "  Stop stack    :  sudo docker compose -f ${COMPOSE_FILE} down"
echo -e "  Start stack   :  sudo docker compose -f ${COMPOSE_FILE} --env-file ${ENV_FILE} up -d"
echo -e "  Restart app   :  sudo docker compose -f ${COMPOSE_FILE} restart app"
echo -e "  Shell into app:  sudo docker exec -it ${CONTAINER_NAME} bash"
echo -e "  occ command   :  sudo docker exec -u www-data ${CONTAINER_NAME} php occ <command>"
echo ""
echo -e "${BOLD}🔐 Security Notice:${RESET}"
echo -e "  Credentials are stored in ${ENV_FILE} (mode: 600)."
echo -e "  Do not expose this file or the web UI without TLS protection."
echo ""
