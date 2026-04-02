#!/usr/bin/env bash
# =============================================================================
# Concourse CI Docker Setup Script
# =============================================================================
#
# DESCRIPTION:
#   Automated setup script for deploying Concourse CI, a continuous integration
#   platform, using Docker Compose. Includes TSA key generation, PostgreSQL
#   database, web UI (ATC), and worker node configuration. Also installs the
#   fly CLI on the host machine.
#
# KEY ACTIONS:
#   1. Pre-flight checks: Verifies Docker installation & daemon
#   2. Idempotency detection: Checks for existing deployment
#   3. RSA key generation: Creates TSA and worker key pairs
#   4. Environment file generation: Creates .env with credentials
#   5. Docker Compose file generation: Creates docker-compose.yml
#   6. Pulls required Docker images (postgres, concourse/concourse)
#   7. Starts the Docker Compose stack in detached mode
#   8. Waits for Concourse web UI to become available (max 120s)
#   9. Installs fly CLI if not present and configures target
#   10. Displays access information and useful management commands
#
# IMPORTANT VARIABLES:
#   CONCOURSE_HOME       - Base installation directory (default: /srv/concourse)
#   CONCOURSE_WEB_PORT   - Host port for web UI (default: 8089)
#   CONCOURSE_ADMIN_USER - Admin username (default: admin)
#   CONCOURSE_ADMIN_PASSWORD - Admin password (auto-generated if not set)
#   CONCOURSE_DB_PASSWORD - Database password (auto-generated if not set)
#   CONCOURSE_CLUSTER_NAME - Display name in UI (default: homelab)
#   CONCOURSE_DNS_SERVER - DNS for worker containers (default: 8.8.8.8)
#   CONCOURSE_TRAEFIK    - Enable Traefik integration (default: false)
#   CONCOURSE_DOMAIN     - Domain for Traefik routing (required when TRAEFIK=true)
#   CONCOURSE_FLY_TARGET - Target name in ~/.flyrc (default: concourse)
#
# DEPENDENCIES:
#   - Docker: Must be installed and daemon must be running
#   - Docker Compose: Required for orchestration
#   - OpenSSL: Used for password and key generation
#   - curl: Used for health check polling
#
# OUTPUTS:
#   - ${CONCOURSE_HOME}/docker-compose.yml - Generated compose configuration
#   - ${CONCOURSE_HOME}/.env              - Secret variables (chmod 600)
#   - ${CONCOURSE_HOME}/keys/web/         - TSA and session keys
#   - ${CONCOURSE_HOME}/keys/worker/      - Worker key pair
#   - ~/.flyrc                            - fly CLI target configuration
#
# USAGE:
#   sudo ./setup-concourse.sh
#   
#   # Or with custom configuration:
#   CONCOURSE_WEB_PORT=9000 CONCOURSE_ADMIN_USER=myuser sudo ./setup-concourse.sh
#
# REFERENCE:
#   Implementation plan: docs/concourse/concourse-ci-implementation-plan.md
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running
# ─────────────────────────────────────────────────────────────────────────────

CONCOURSE_HOME="${CONCOURSE_HOME:-/srv/concourse}"          # Base installation directory
CONCOURSE_WEB_PORT="${CONCOURSE_WEB_PORT:-8089}"            # Host port for web UI
CONCOURSE_ADMIN_USER="${CONCOURSE_ADMIN_USER:-admin}"       # Admin username
CONCOURSE_ADMIN_PASSWORD="${CONCOURSE_ADMIN_PASSWORD:-}"    # Auto-generated if empty
CONCOURSE_DB_PASSWORD="${CONCOURSE_DB_PASSWORD:-}"          # Auto-generated if empty
CONCOURSE_CLUSTER_NAME="${CONCOURSE_CLUSTER_NAME:-homelab}" # Display name in UI
CONCOURSE_DNS_SERVER="${CONCOURSE_DNS_SERVER:-8.8.8.8}"     # DNS for workers
CONCOURSE_EXTERNAL_URL="${CONCOURSE_EXTERNAL_URL:-}"        # Auto-detected if empty
CONCOURSE_FLY_TARGET="${CONCOURSE_FLY_TARGET:-concourse}"   # Target name in ~/.flyrc

# Traefik integration (optional)
CONCOURSE_TRAEFIK="${CONCOURSE_TRAEFIK:-false}"             # Set to "true" to enable
CONCOURSE_DOMAIN="${CONCOURSE_DOMAIN:-}"                    # e.g. concourse.example.com
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"                     # Traefik's network name

# ─────────────────────────────────────────────────────────────────────────────
# SOURCE SHARED LIBRARIES
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/helpers.sh"

# Source core library for Traefik integration (optional)
if [[ "$CONCOURSE_TRAEFIK" == "true" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/core.sh" || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

step "Running pre-flight checks"
run_preflight_checks

# Traefik pre-flight (only when opt-in)
if [[ "$CONCOURSE_TRAEFIK" == "true" ]]; then
  ensure_proxy_network
  if [[ -z "$CONCOURSE_DOMAIN" ]]; then
    error "CONCOURSE_DOMAIN must be set when CONCOURSE_TRAEFIK=true."
  fi
fi

# Port availability check (when not using Traefik)
if [[ "$CONCOURSE_TRAEFIK" == "false" ]]; then
  if ss -tln 2>/dev/null | grep -qE ":${CONCOURSE_WEB_PORT}[[:space:]]"; then
    warn "Port ${CONCOURSE_WEB_PORT} is already in use."
    warn "Either stop the existing service or choose a different CONCOURSE_WEB_PORT."
    read -rp "    Continue anyway? [y/N] " answer
    [[ "${answer,,}" == "y" ]] || exit 0
  else
    info "Port ${CONCOURSE_WEB_PORT} is available."
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# IDEMPOTENCY DETECTION
# ─────────────────────────────────────────────────────────────────────────────

step "Checking for existing Concourse deployment"

COMPOSE_FILE="${CONCOURSE_HOME}/docker-compose.yml"
ENV_FILE="${CONCOURSE_HOME}/.env"

if [[ -f "$COMPOSE_FILE" ]]; then
  warn "Existing docker-compose.yml found at ${COMPOSE_FILE}."
  warn "This will re-create the Concourse stack."
  
  # Preserve RSA keys - they are bind-mounted and will survive re-deployment
  if [[ -d "${CONCOURSE_HOME}/keys" ]]; then
    info "RSA keys in ${CONCOURSE_HOME}/keys/ will be preserved for session continuity."
  fi
  
  # PostgreSQL data is in a named volume and will persist automatically
  info "PostgreSQL data volume will persist across re-deployment."
  
  read -rp "    Re-create stack? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    info "Stopping and removing existing stack..."
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    success "Old stack removed. Keys and database data preserved."
  else
    info "Keeping existing stack. Exiting."
    exit 0
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CREATE DIRECTORY STRUCTURE
# ─────────────────────────────────────────────────────────────────────────────

step "Creating directory structure under ${CONCOURSE_HOME}"

# Create the base CONCOURSE_HOME directory if it doesn't exist
if [[ ! -d "${CONCOURSE_HOME}" ]]; then
  if ! mkdir -p "${CONCOURSE_HOME}" 2>/dev/null; then
    error "Failed to create ${CONCOURSE_HOME}. Check permissions."
    exit 1
  fi
fi

# Create subdirectories for keys
mkdir -p "${CONCOURSE_HOME}/keys/web"
mkdir -p "${CONCOURSE_HOME}/keys/worker"

# Ensure directories are accessible by Docker daemon
# Add current user to docker group if not already a member
if ! id -nG | grep -qw "$USER" | grep -qw docker; then
  # Note: This may fail if not running as root, but that's expected
  # The user will need to add themselves to docker group manually if needed
  if id -u &>/dev/null; then
    if ! groups "$USER" | grep -qw docker; then
      info "Note: Add user '$USER' to docker group for Docker access: sudo usermod -aG docker $USER"
    fi
  fi
fi

# Verify directories were created successfully
if [[ ! -d "${CONCOURSE_HOME}/keys/web" ]] || [[ ! -d "${CONCOURSE_HOME}/keys/worker" ]]; then
  error "Failed to create required subdirectories under ${CONCOURSE_HOME}"
  exit 1
fi

success "Directories created."

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE RSA KEY PAIRS
# ─────────────────────────────────────────────────────────────────────────────

step "Generating RSA key pairs for TSA authentication"

# Generate keys only if they don't exist (idempotent)
if [[ ! -f "${CONCOURSE_HOME}/keys/web/tsa_host_key" ]]; then
  info "Generating TSA host key pair..."
  openssl genrsa -out "${CONCOURSE_HOME}/keys/web/tsa_host_key" 2048
  openssl rsa -in "${CONCOURSE_HOME}/keys/web/tsa_host_key" \
    -pubout -out "${CONCOURSE_HOME}/keys/web/tsa_host_key.pub"
fi

if [[ ! -f "${CONCOURSE_HOME}/keys/web/session_signing_key" ]]; then
  info "Generating session signing key pair..."
  openssl genrsa -out "${CONCOURSE_HOME}/keys/web/session_signing_key" 2048
  openssl rsa -in "${CONCOURSE_HOME}/keys/web/session_signing_key" \
    -pubout -out "${CONCOURSE_HOME}/keys/web/session_signing_key.pub"
fi

if [[ ! -f "${CONCOURSE_HOME}/keys/worker/worker_key" ]]; then
  info "Generating worker key pair..."
  openssl genrsa -out "${CONCOURSE_HOME}/keys/worker/worker_key" 2048
  openssl rsa -in "${CONCOURSE_HOME}/keys/worker/worker_key" \
    -pubout -out "${CONCOURSE_HOME}/keys/worker/worker_key.pub"
fi

# Create authorized_worker_keys (copy of worker public key)
if [[ ! -f "${CONCOURSE_HOME}/keys/web/authorized_worker_keys" ]]; then
  cp "${CONCOURSE_HOME}/keys/worker/worker_key.pub" \
     "${CONCOURSE_HOME}/keys/web/authorized_worker_keys"
fi

# Set permissions
chmod -R 700 "${CONCOURSE_HOME}/keys/"

success "Keys generated and permissions set."

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE ENVIRONMENT FILE
# ─────────────────────────────────────────────────────────────────────────────

step "Generating ${ENV_FILE}"

# Generate passwords if not already set
if [[ -z "$CONCOURSE_ADMIN_PASSWORD" ]]; then
  CONCOURSE_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
fi

if [[ -z "$CONCOURSE_DB_PASSWORD" ]]; then
  CONCOURSE_DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
fi

# Detect external URL if not set
if [[ -z "$CONCOURSE_EXTERNAL_URL" ]]; then
  LAN_IP=$(hostname -I | awk '{print $1}')
  CONCOURSE_EXTERNAL_URL="http://${LAN_IP}:${CONCOURSE_WEB_PORT}"
fi

# Write .env file
cat > "${ENV_FILE}" <<EOF
# Concourse CI Configuration
# Generated: $(date -Iseconds)

# Database
CONCOURSE_DB_USER=concourse
CONCOURSE_DB_PASSWORD=${CONCOURSE_DB_PASSWORD}

# Web Node
CONCOURSE_EXTERNAL_URL=${CONCOURSE_EXTERNAL_URL}
CONCOURSE_WEB_PORT=${CONCOURSE_WEB_PORT}
CONCOURSE_CLUSTER_NAME=${CONCOURSE_CLUSTER_NAME}

# Authentication
CONCOURSE_ADMIN_USER=${CONCOURSE_ADMIN_USER}
CONCOURSE_ADMIN_PASSWORD=${CONCOURSE_ADMIN_PASSWORD}

# Worker Configuration
CONCOURSE_DNS_SERVER=${CONCOURSE_DNS_SERVER}
EOF

chmod 600 "${ENV_FILE}"

success "Environment file written with auto-generated credentials."

# Store for later use (fly CLI login)
STORED_ADMIN_PASSWORD="$CONCOURSE_ADMIN_PASSWORD"

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE DOCKER COMPOSE FILE
# ─────────────────────────────────────────────────────────────────────────────

step "Generating ${COMPOSE_FILE}"

# Build networks section
SECTION_NETWORKS="networks:
  concourse-net:
    driver: bridge"

if [[ "$CONCOURSE_TRAEFIK" == "true" ]]; then
  SECTION_NETWORKS+="
  ${PROXY_NETWORK}:
    external: true"
fi

# Build web service ports section
SECTION_WEB_PORTS="    ports:"
if [[ "$CONCOURSE_TRAEFIK" == "false" ]]; then
  SECTION_WEB_PORTS+="
      - \"${CONCOURSE_WEB_PORT}:8080\"  # Web UI (HTTP)
      - \"2222:2222\"                   # TSA (internal worker registration)"
else
  # When using Traefik, ports are exposed via labels
  SECTION_WEB_PORTS+="
      - \"2222:2222\"                   # TSA (internal worker registration)"
fi

# Build web service labels section (Traefik only)
SECTION_WEB_LABELS=""
if [[ "$CONCOURSE_TRAEFIK" == "true" ]]; then
  SECTION_WEB_LABELS="    labels:
      - \"traefik.enable=true\"
      - \"traefik.docker.network=${PROXY_NETWORK}\"
      - \"traefik.http.routers.concourse.rule=Host:${CONCOURSE_DOMAIN}\"
      - \"traefik.http.routers.concourse.entrypoints=websecure\"
      - \"traefik.http.routers.concourse.tls.certresolver=letsencrypt\"
      - \"traefik.http.services.concourse.loadbalancer.server.port=8080\""
fi

# Build compose file - use temp script approach to avoid heredoc nesting issues
# Write directly to a temp file, then move it into place
COMPOSE_TEMP=$(mktempfile)

cat > "$COMPOSE_TEMP" <<'EOF'
version: "3.9"

NETWORKS_PLACEHOLDER

services:
  concourse-db:
    image: postgres:15
    container_name: concourse-db
    restart: always
    environment:
      - POSTGRES_USER=concourse
      - POSTGRES_PASSWORD=\${CONCOURSE_DB_PASSWORD}
      - POSTGRES_DB=concourse
    networks:
      - concourse-net
    volumes:
      - concourse-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U concourse -d concourse"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  concourse-web:
    image: concourse/concourse:latest
    container_name: concourse-web
    restart: always
    depends_on:
      concourse-db:
        condition: service_healthy
    environment:
      - CONCOURSE_POSTGRES_HOST=concourse-db
      - CONCOURSE_EXTERNAL_URL=\${CONCOURSE_EXTERNAL_URL}
      - CONCOURSE_TSA_HOST_KEY=/concourse-keys/web/tsa_host_key
      - CONCOURSE_SESSION_SIGNING_KEY=/concourse-keys/web/session_signing_key
      - CONCOURSE_TSA_AUTHORIZED_KEYS=/concourse-keys/web/authorized_worker_keys
      - CONCOURSE_CLUSTER_NAME=\${CONCOURSE_CLUSTER_NAME}



PORTS_PLACEHOLDER
LABELS_PLACEHOLDER

  cat <<'WORKER_START'
    volumes:
      - ./keys:/concourse-keys
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "10"

  concourse-worker:
    image: concourse/concourse:latest
    container_name: concourse-worker
    restart: always
    privileged: true
    stop_signal: SIGUSR2
    environment:
      - CONCOURSE_TSA_HOST=concourse-web:2222
      - CONCOURSE_TSA_PUBLIC_KEY=/concourse-keys/web/tsa_host_key.pub
      - CONCOURSE_TSA_WORKER_PRIVATE_KEY=/concourse-keys/worker/worker_key
      - CONCOURSE_BAGGAGECLAIM_DRIVER=overlay
      - CONCOURSE_RUNTIME=containerd
      - CONCOURSE_DNS_SERVER=\${CONCOURSE_DNS_SERVER}
    networks:
      - concourse-net
    volumes:
      - ./keys:/concourse-keys
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "10"

volumes:
  concourse-db-data:
EOF

# Replace placeholders with actual values
sed -i \
  -e "s|NETWORKS_PLACEHOLDER|${SECTION_NETWORKS}|" \
  -e "/^LABELS_PLACEHOLDER$/d" \
  "$COMPOSE_TEMP"

# Handle ports section (remove placeholder if Traefik, otherwise replace)
if [[ "$CONCOURSE_TRAEFIK" == "true" ]]; then
  sed -i 's|PORTS_PLACEHOLDER||' "$COMPOSE_TEMP"
else
  # Replace PORTS_PLACEHOLDER with actual ports, but remove leading newline
  sed -i "s|PORTS_PLACEHOLDER|\
${SECTION_WEB_PORTS}|" "$COMPOSE_TEMP"
fi

# Add labels after concourse-web network section (only when Traefik enabled)
if [[ -n "$SECTION_WEB_LABELS" ]]; then
  sed -i "/^    networks:$/a\\${SECTION_WEB_LABELS}" "$COMPOSE_TEMP"
fi

# Move to final location
mv "$COMPOSE_TEMP" "$COMPOSE_FILE"

success "Docker Compose file written to ${COMPOSE_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
# PULL IMAGES
# ─────────────────────────────────────────────────────────────────────────────

step "Pulling Docker images"
docker compose -f "$COMPOSE_FILE" pull
success "Images pulled."

# ─────────────────────────────────────────────────────────────────────────────
# START THE STACK
# ─────────────────────────────────────────────────────────────────────────────

step "Starting Concourse stack (detached)"
docker compose -f "$COMPOSE_FILE" up -d
success "Stack started."

# ─────────────────────────────────────────────────────────────────────────────
# WAIT FOR CONCOURSE TO BECOME AVAILABLE
# ─────────────────────────────────────────────────────────────────────────────

step "Waiting for Concourse web UI to respond"

MAX_WAIT=120
INTERVAL=5
ELAPSED=0
READY=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  # When using Traefik, check via container; otherwise use localhost
  if [[ "$CONCOURSE_TRAEFIK" == "true" ]]; then
    HTTP_CODE=$(docker exec concourse-web curl -s -o /dev/null -w "%{http_code}" \
      "http://localhost:8080/api/v1/info" 2>/dev/null) || true
  else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      "http://localhost:${CONCOURSE_WEB_PORT}/api/v1/info")
  fi
  
  if [[ "$HTTP_CODE" =~ ^(200|302|303)$ ]]; then
    READY=true
    break
  fi
  
  echo -ne "\r    Waited ${ELAPSED}s / ${MAX_WAIT}s ..."
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""

if [[ "$READY" == "true" ]]; then
  if [[ "$CONCOURSE_TRAEFIK" == "true" ]]; then
    success "Concourse is up and responding via Traefik!"
  else
    success "Concourse is up and responding on port ${CONCOURSE_WEB_PORT}!"
  fi
else
  warn "Concourse did not respond within ${MAX_WAIT}s."
  warn "It may still be starting. Check logs with:"
  warn "  docker compose -f ${COMPOSE_FILE} logs -f"
fi

# ─────────────────────────────────────────────────────────────────────────────
# INSTALL FLY CLI (if not present)
# ─────────────────────────────────────────────────────────────────────────────

step "Checking fly CLI installation"

if command -v fly &>/dev/null; then
  info "Fly CLI already installed at $(command -v fly)"
  INSTALL_FLY=false
else
  INSTALL_FLY=true
fi

if [[ "$INSTALL_FLY" == "true" ]]; then
  step "Installing fly CLI"
  
  # Detect architecture
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) PLATFORM="amd64" ;;
    aarch64|arm64) PLATFORM="arm64" ;;
    *) error "Unsupported architecture: $ARCH";;
  esac
  
  info "Detected architecture: ${ARCH} (${PLATFORM})"
  
  # Download fly CLI
  info "Downloading fly CLI from Concourse web UI..."
  curl -fsSL \
    "${CONCOURSE_EXTERNAL_URL}/api/v1/cli?arch=${PLATFORM}&platform=linux" \
    -o /tmp/fly
  
  # Verify download
  if ! file /tmp/fly | grep -q "ELF 64-bit"; then
    error "Downloaded file is not a valid ELF binary"
  fi
  
  success "Download verified."
  
  # Install
  sudo install -m 0755 /tmp/fly /usr/local/bin/fly
  fly --version
  success "Fly CLI installed at /usr/local/bin/fly"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURE FLY TARGET
# ─────────────────────────────────────────────────────────────────────────────

step "Configuring fly target: ${CONCOURSE_FLY_TARGET}"

fly -t "${CONCOURSE_FLY_TARGET}" login \
  --concourse-url "${CONCOURSE_EXTERNAL_URL}" \
  --username "${CONCOURSE_ADMIN_USER}" \
  --password "${STORED_ADMIN_PASSWORD}"

success "Target configured in ~/.flyrc"

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Concourse setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Web UI${RESET}           ${CONCOURSE_EXTERNAL_URL}"
echo -e "  ${BOLD}Admin User${RESET}       ${CONCOURSE_ADMIN_USER}"
echo -e "  ${BOLD}Admin Password${RESET}   ${STORED_ADMIN_PASSWORD}"
echo -e "  ${BOLD}Database${RESET}         PostgreSQL (internal)"
echo -e "  ${BOLD}Data directory${RESET}   ${CONCOURSE_HOME}"
echo -e "  ${BOLD}Compose file${RESET}     ${COMPOSE_FILE}"
echo -e "  ${BOLD}Fly target${RESET}       ${CONCOURSE_FLY_TARGET}"
echo ""
echo -e "${YELLOW}  First-time setup:${RESET}"
echo -e "  Open the Web UI and create your first pipeline."
echo ""
echo -e "${BOLD}Useful commands:${RESET}"
echo -e "  Follow logs    :  docker compose -f ${COMPOSE_FILE} logs -f"
echo -e "  Stop stack     :  docker compose -f ${COMPOSE_FILE} down"
echo -e "  Start stack    :  docker compose -f ${COMPOSE_FILE} up -d"
echo -e "  Shell into web :  docker exec -it concourse-web bash"
echo ""
echo -e "${BOLD}Fly CLI:${RESET}"
echo -e "  Target           : ${CONCOURSE_FLY_TARGET}"
echo -e "  Login command    : fly -t ${CONCOURSE_FLY_TARGET} login -c ${CONCOURSE_EXTERNAL_URL} -u ${CONCOURSE_ADMIN_USER} -p <password>"
echo -e "  List pipelines   : fly -t ${CONCOURSE_FLY_TARGET} pipelines"
echo -e "  Trigger job      : fly -t ${CONCOURSE_FLY_TARGET} trigger-job -j pipeline/job --watch"
echo ""
