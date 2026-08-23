#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-planka.sh — Install Planka Kanban board
# =============================================================================
#
# Description:
#   Deploys Planka, a self-hosted Kanban board, using Docker Compose.
#
# Usage:
#   ./setup-planka.sh                 # install with defaults
#   ./setup-planka.sh --help          # show help and all configuration options
#
# All configuration is done via environment variables — run with --help for
# the full list (PLANKA_HOME, BASE_URL, PLANKA_HOST_IP, PLANKA_EXTRA_ORIGINS, ...).
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
# USAGE / HELP
# ─────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [OPTIONS]

Deploys Planka (self-hosted Kanban board) using Docker Compose.
Data is stored under PLANKA_HOME (default: /srv/planka).

${BOLD}Options:${RESET}
  -h, --help    Show this help and exit

${BOLD}Environment variables${RESET} (all optional):

  Application:
    PLANKA_HOME             Data directory (default: /srv/planka)
    PLANKA_IMAGE            Container image (default: ghcr.io/plankanban/planka:latest)
    CONTAINER_NAME          Container name (default: planka)
    BASE_URL                Base URL for Planka, and the allowlist of origins Planka
                            accepts socket.io (WebSocket) connections from.
                            Comma-separated list of URLs — every host:port a browser
                            may use to reach Planka must be listed, otherwise
                            realtime features break (Planka's sails config
                            onlyAllowOrigins). Default: http://localhost:HTTP_PORT
                            plus the detected LAN IP (direct mode), or
                            https://PLANKA_DOMAIN (Traefik mode).
    PLANKA_HOST_IP          Host IP used to build the default LAN origin
                            (default: auto-detected, first non-loopback IPv4)
    PLANKA_EXTRA_ORIGINS    Extra comma-separated origins to allow, e.g.
                            http://evobox:1337,http://100.64.0.2:1337
    HTTP_PORT               Host port (default: 1337, ignored when PLANKA_TRAEFIK=true)
    SECRET_KEY              App secret (auto-generated if empty)

  Traefik reverse-proxy integration (opt-in):
    PLANKA_TRAEFIK          Set to "true" to enable Traefik routing (default: false)
    PLANKA_DOMAIN           Domain for Traefik access (required when PLANKA_TRAEFIK=true)
    PROXY_NETWORK           Traefik's external Docker network name (default: proxy)

  PostgreSQL:
    POSTGRES_DB             Database name (default: planka)
    POSTGRES_USER           Database user (default: postgres)
    POSTGRES_PASSWORD       Database password (default: empty = trust auth, dev only)

  Admin user:
    ADMIN_EMAIL             Create admin user non-interactively
                            (default: empty = prompt interactively after startup)
    ADMIN_PASSWORD          Admin password
    ADMIN_NAME              Admin display name (default: Admin)
    ADMIN_USERNAME          Admin username (optional, forwarded to Planka)

${BOLD}Examples:${RESET}
  $0
  HTTP_PORT=8080 $0
  PLANKA_TRAEFIK=true PLANKA_DOMAIN=planka.example.com $0
  ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=secret $0
EOF
  exit 0
}


# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    *) error "Unknown option: $1 (use --help for usage)" ;;
  esac
  shift
done


# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running (or export them)
# ─────────────────────────────────────────────────────────────────────────────

PLANKA_HOME="${PLANKA_HOME:-/srv/planka}"
PLANKA_IMAGE="${PLANKA_IMAGE:-ghcr.io/plankanban/planka:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-planka}"

HTTP_PORT="${HTTP_PORT:-1337}"
# BASE_URL may stay empty — it is resolved below (localhost + LAN IP by default).
# It doubles as Planka's socket.io origin allowlist (comma-separated URLs).
BASE_URL="${BASE_URL:-}"
PLANKA_HOST_IP="${PLANKA_HOST_IP:-}"
PLANKA_EXTRA_ORIGINS="${PLANKA_EXTRA_ORIGINS:-}"

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
# LOCAL HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# First non-loopback IPv4 address of this host (empty output if none found).
detect_lan_ip() {
  local ip
  for ip in $(hostname -I 2>/dev/null); do
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$ip" != 127.* && "$ip" != 169.254.* ]]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

# Collapse a comma-separated list: trim whitespace, drop empties, dedupe (order kept).
dedupe_csv() {
  printf '%s\n' "$1" | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk 'NF && !seen[$0]++' \
    | paste -sd',' -
}


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
# RESOLVE BASE_URL (also Planka's socket.io origin allowlist)
# ─────────────────────────────────────────────────────────────────────────────
#
# Planka whitelists WebSocket origins from BASE_URL: it accepts a comma-separated
# list of URLs and only accepts socket.io connections from those origins
# (server/config/env/production.js: onlyAllowOrigins). Every host:port a browser
# may use to reach Planka must be listed, otherwise the WebSocket handshake is
# rejected and realtime features break.

step "Resolving BASE_URL (socket origin allowlist)"

LAN_IP="${PLANKA_HOST_IP:-}"

if [[ "$PLANKA_TRAEFIK" != "true" && -z "$BASE_URL" ]]; then
  BASE_URL="http://localhost:${HTTP_PORT}"
  if [[ -z "$LAN_IP" ]]; then
    LAN_IP="$(detect_lan_ip || true)"
  fi
  if [[ -n "$LAN_IP" ]]; then
    BASE_URL="${BASE_URL},http://${LAN_IP}:${HTTP_PORT}"
    info "Included LAN origin http://${LAN_IP}:${HTTP_PORT} (override with PLANKA_HOST_IP)."
  else
    warn "Could not detect a LAN IP — allowlist is localhost only. Set PLANKA_HOST_IP for LAN access."
  fi
fi

if [[ -n "$PLANKA_EXTRA_ORIGINS" ]]; then
  BASE_URL="${BASE_URL},${PLANKA_EXTRA_ORIGINS}"
fi
BASE_URL="$(dedupe_csv "$BASE_URL")"

# Warn if the allowlist only covers loopback — LAN browsers would be rejected.
IFS=',' read -ra _allowlist <<< "$BASE_URL"
_loopback_only=true
for _entry in "${_allowlist[@]}"; do
  _host="${_entry#*://}"; _host="${_host%%/*}"; _host="${_host%%:*}"
  if [[ "$_host" != "localhost" && "$_host" != "127.0.0.1" ]]; then
    _loopback_only=false
    break
  fi
done
if [[ "$_loopback_only" == "true" ]]; then
  warn "BASE_URL only contains loopback origins — browsers on other machines will"
  warn "fail the WebSocket handshake (realtime features break). Add e.g."
  warn "PLANKA_HOST_IP=<your host IP> or PLANKA_EXTRA_ORIGINS=http://<host>:${HTTP_PORT}"
fi

success "BASE_URL: ${BASE_URL}"


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
    restart: unless-stopped
$(if [[ "$PLANKA_TRAEFIK" != "true" ]]; then echo '    ports:'; echo "      - \"${HTTP_PORT}:1337\"  # Access via http://localhost:${HTTP_PORT}${LAN_IP:+, http://${LAN_IP}:${HTTP_PORT}}"; fi)
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
$(if [[ "$PLANKA_TRAEFIK" == "true" ]]; then echo '      - proxy'; echo '    labels:'; echo '      - "traefik.enable=true"'; echo "      - \"traefik.docker.network=$PROXY_NETWORK\""; echo "      - \"traefik.http.routers.planka.rule=Host(\`$PLANKA_DOMAIN\`)\""; echo '      - "traefik.http.routers.planka.entrypoints=websecure"'; echo '      - "traefik.http.routers.planka.tls.certresolver=letsencrypt"'; echo '      - "traefik.http.services.planka.loadbalancer.server.port=1337"'; fi)
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    container_name: ${CONTAINER_NAME}-postgres
    restart: unless-stopped
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
$(if [[ "$PLANKA_TRAEFIK" == "true" ]]; then echo '  proxy:'; echo '    external: true'; fi)
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
  if echo "$HTTP_CODE" | grep -qE "^(200|302|303|401)"; then
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
  if docker compose -f "$COMPOSE_FILE" run --rm planka \
    npm run db:create-admin-user -- \
      --email "${ADMIN_EMAIL}" \
      --password "${ADMIN_PASSWORD}" \
      --name "${ADMIN_NAME}" \
      ${ADMIN_USERNAME:+--username "${ADMIN_USERNAME}"}
  then
    success "Admin user '${ADMIN_EMAIL}' created."
  else
    warn "Admin user creation failed — the user may already exist, or Planka is still initialising."
  fi
else
  info "No ADMIN_EMAIL/ADMIN_PASSWORD provided — run interactively now:"
  echo ""
  echo -e "  ${BOLD}docker compose -f ${COMPOSE_FILE} run --rm planka npm run db:create-admin-user${RESET}"
  echo ""
  read -rp "    Create admin user interactively now? [Y/n] " _create
  if [[ "${_create,,}" != "n" ]]; then
    if docker compose -f "$COMPOSE_FILE" run --rm planka npm run db:create-admin-user
    then
      success "Admin user created."
    else
      warn "Interactive admin creation exited with an error. You can re-run the command above later."
    fi
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
  if [[ -n "$LAN_IP" ]]; then
    echo -e "  ${BOLD}LAN access${RESET}       http://${LAN_IP}:${HTTP_PORT}"
  fi
fi
echo -e "  ${BOLD}Socket origins${RESET}   ${BASE_URL}"
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
