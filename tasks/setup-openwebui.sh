#!/usr/bin/env bash
# shellcheck disable=SC2086,SC1091
# =============================================================================
# Open WebUI Docker Setup Script
# =============================================================================
#
# DESCRIPTION:
#   This script automates the installation and configuration of Open WebUI
#   using Docker Compose. It sets up Open WebUI to connect to an external
#   LM Studio instance for AI model inference.
#
# KEY ACTIONS:
#   1. Pre-flight checks: Verifies Docker installation & daemon, port availability
#   2. Checks if an existing Open WebUI container/compose stack is running
#   3. Generates a secure secret key (stored in .env file for security)
#   4. Creates docker-compose.yml with Traefik or direct access mode
#   5. Pulls required Docker images
#   6. Starts the Docker Compose stack in detached mode
#   7. Waits for Open WebUI to become available (max 120s)
#   8. Displays access information and useful management commands
#
# IMPORTANT VARIABLES:
#   OPENWEBUI_PORT     - Host port for direct web UI access (default: 3333)
#   LM_STUDIO_PORT     - Port where LM Studio API is listening (default: 1234)
#   PROJECT_DIR        - Installation directory (default: /srv/openwebui)
#   WEBUI_SECRET_KEY   - Custom secret key (auto-generated if not set, stored in .env)
#   
#   Traefik reverse-proxy integration (opt-in):
#   OPENWEBUI_TRAEFIK  - Set to "true" to enable Traefik routing (default: false)
#   OPENWEBUI_DOMAIN   - Domain for Traefik access (required when Traefik=true)
#   PROXY_NETWORK      - Traefik's external Docker network name (default: proxy)
#
# DEPENDENCIES:
#   - Docker: Must be installed and daemon must be running
#   - LM Studio running locally on port $LM_STUDIO_PORT
#   - Docker Compose v2+ recommended
#   - openssl: Used for generating secure secret key
#   - curl: Used for health check polling
#   - Traefik instance with proxy network (when OPENWEBUI_TRAEFIK=true)
#
# OUTPUTS:
#   - ${PROJECT_DIR}/docker-compose.yml - Generated compose configuration
#   - ${PROJECT_DIR}/.env            - Secret key and environment variables (secure)
#   - ${PROJECT_DIR}/start_openwebui.sh - Convenience startup script
#   - Persistent data volume: openwebui_data
#
# USAGE:
#   ./setup-openwebui.sh
#   
#   # Or with custom ports:
#   OPENWEBUI_PORT=8080 LM_STUDIO_PORT=5000 ./setup-openwebui.sh
#   
#   # With Traefik integration:
#   OPENWEBUI_TRAEFIK=true OPENWEBUI_DOMAIN=openwebui.example.com ./setup-openwebui.sh
#
#   # Show help:
#   ./setup-openwebui.sh --help
#
# REFERENCE:
#   https://openwebui.com/docs/
#
# =============================================================================

set -euo pipefail

# Determine script directory and template location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../templates/openwebui"

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP TRAP — handles partial failures
# ─────────────────────────────────────────────────────────────────────────────

cleanup_on_failure() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo ""
    warn "Setup failed (exit code: ${exit_code})! Cleaning up..."
    if [[ -d "$PROJECT_DIR" ]] && docker compose ps &>/dev/null; then
      docker compose down --remove-orphans 2>/dev/null || true
      info "Removed partially created stack."
    fi
  fi
}

trap cleanup_on_failure EXIT

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running
# ─────────────────────────────────────────────────────────────────────────────

OPENWEBUI_PORT="${OPENWEBUI_PORT:-3333}"          # Host port for web UI (direct mode)
LM_STUDIO_PORT="${LM_STUDIO_PORT:-1234}"          # LM Studio API port
PROJECT_DIR="${PROJECT_DIR:-/srv/openwebui}"       # Installation directory

# Secret key for Open WebUI authentication (auto-generated if not set)
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-}"

# Traefik reverse-proxy integration (opt-in)
OPENWEBUI_TRAEFIK="${OPENWEBUI_TRAEFIK:-false}"   # Set to "true" to enable Traefik routing
OPENWEBUI_DOMAIN="${OPENWEBUI_DOMAIN:-}"          # e.g. openwebui.example.com (required when Traefik=true)
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"           # Traefik's external Docker network name

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
Usage: $0 [OPTIONS]

Installs and configures Open WebUI using Docker Compose, connecting to an
external LM Studio instance for AI model inference. Supports direct host
port access or Traefik reverse-proxy integration.

Options:
  --interactive   Prompt for confirmation on risky conditions
  -h, --help      Show this help and exit

Environment variables (all optional):
  OPENWEBUI_PORT     Host port for direct web UI access (default: 3333)
  LM_STUDIO_PORT     Port where LM Studio API is listening (default: 1234)
  PROJECT_DIR        Installation directory (default: /srv/openwebui)
  WEBUI_SECRET_KEY   Custom secret key (auto-generated if not set, stored in .env)
  OPENWEBUI_TRAEFIK  Set to "true" to enable Traefik routing (default: false)
  OPENWEBUI_DOMAIN   Domain for Traefik access (required when OPENWEBUI_TRAEFIK=true)
  PROXY_NETWORK      Traefik's external Docker network name (default: proxy)

Note: LM Studio must be running on LM_STUDIO_PORT.
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

# Check Docker Compose version (v2+ recommended)
COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "0.0.0")
COMPOSE_MAJOR=$(echo "$COMPOSE_VERSION" | cut -d'.' -f1)
if [[ "$COMPOSE_MAJOR" -lt 2 ]]; then
  warn "Docker Compose v2+ recommended. Current version: ${COMPOSE_VERSION}"
fi

# Check for openssl (required for secret key generation)
if [[ -z "$WEBUI_SECRET_KEY" ]] && ! command -v openssl &>/dev/null; then
  error "openssl is not installed. Required for generating secure secret key. Install it or set WEBUI_SECRET_KEY manually."
fi

# Check for envsubst (required for template rendering)
if ! command -v envsubst &>/dev/null; then
  error "envsubst is not installed. Required for template rendering. Install with: sudo apt-get install gettext-base"
fi

# Check if port is already in use (direct mode only)
if [[ "$OPENWEBUI_TRAEFIK" != "true" ]]; then
  if ss -tln 2>/dev/null | grep -q ":${OPENWEBUI_PORT} " || \
     netstat -tln 2>/dev/null | grep -q ":${OPENWEBUI_PORT} "; then
    error "Port ${OPENWEBUI_PORT} is already in use. Choose a different OPENWEBUI_PORT."
  fi
fi

# Traefik pre-flight (only when opt-in)
if [[ "$OPENWEBUI_TRAEFIK" == "true" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/helpers.sh"
  if ! ensure_proxy_network; then
    error "Traefik proxy network '${PROXY_NETWORK}' not found or inaccessible."
  fi
  if [[ -z "$OPENWEBUI_DOMAIN" ]]; then
    error "OPENWEBUI_DOMAIN must be set when OPENWEBUI_TRAEFIK=true."
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK FOR EXISTING STACK
# ─────────────────────────────────────────────────────────────────────────────

step "Checking for existing Open WebUI stack"

COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
  warn "Existing docker-compose.yml found at ${COMPOSE_FILE}."
  echo ""
  info "${BOLD}IMPORTANT:${RESET} Your data in 'openwebui_data' volume will be PRESERVED."
  info "However, resetting the stack may break references to old configurations."
  if [[ "$INTERACTIVE" == "true" ]]; then
    read -rp "    Are you sure you want to re-create the stack? [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
      info "Stopping and removing existing stack..."
      cd "$PROJECT_DIR"
      docker compose down 2>/dev/null || true
      success "Old stack removed. Data volume preserved."
    else
      info "Keeping existing stack. Exiting."
      exit 0
    fi
  else
    # Do not let the failure-cleanup trap tear down a pre-existing stack.
    trap - EXIT
    error "Existing Open WebUI stack detected at ${PROJECT_DIR}. Re-run with --interactive to re-create the stack, or remove ${COMPOSE_FILE} manually."
  fi
fi

# Check if LM Studio is available (warning, not fatal)
step "Checking LM Studio availability"

if curl -s --connect-timeout 2 "http://localhost:${LM_STUDIO_PORT}/v1" &>/dev/null; then
  success "LM Studio detected on port ${LM_STUDIO_PORT}."
else
  warn "LM Studio not responding on port ${LM_STUDIO_PORT}."
  warn "Open WebUI will start but won't be able to connect to models until LM Studio is running."
  warn "Start LM Studio with: lmstudio"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEMPLATE RENDERERS — generated artifacts live in templates/openwebui/
# (AGENTS.md: no inline templates in scripts). The conditional compose
# structure is split into docker-compose.direct.yml / docker-compose.traefik.yml
# variant files, mirroring templates/opencode-server/.
# ─────────────────────────────────────────────────────────────────────────────

# Render .env from templates/openwebui/env.template.
# Existing .env files are backed up to .env.bak first (user-edit preservation).
_generate_env_file() {
  local env_file="$1"

  if [[ -f "$env_file" ]]; then
    warn "Existing .env file found. Backing up to ${env_file}.bak"
    cp "$env_file" "${env_file}.bak"
  fi

  export WEBUI_SECRET_KEY
  # shellcheck disable=SC2016  # envsubst expects the literal variable list
  envsubst '${WEBUI_SECRET_KEY}' \
    < "${TEMPLATE_DIR}/env.template" > "$env_file"
  chmod 600 "$env_file"
}

# Render docker-compose.yml from the matching template variant
_generate_compose_file() {
  local compose_file="$1"
  local compose_template

  if [[ "$OPENWEBUI_TRAEFIK" == "true" ]]; then
    compose_template="${TEMPLATE_DIR}/docker-compose.traefik.yml"
  else
    compose_template="${TEMPLATE_DIR}/docker-compose.direct.yml"
  fi

  GENERATED_DATE="$(date -Iseconds)"
  export GENERATED_DATE OPENWEBUI_PORT LM_STUDIO_PORT WEBUI_SECRET_KEY \
    PROXY_NETWORK OPENWEBUI_DOMAIN
  # shellcheck disable=SC2016  # envsubst expects the literal variable list
  envsubst '${GENERATED_DATE} ${OPENWEBUI_PORT} ${LM_STUDIO_PORT} ${WEBUI_SECRET_KEY} ${PROXY_NETWORK} ${OPENWEBUI_DOMAIN}' \
    < "$compose_template" > "$compose_file"
}

# Install the static start script (no dynamic values — plain copy)
_generate_start_script() {
  local start_script="$1"

  cp "${TEMPLATE_DIR}/start_openwebui.sh" "$start_script"
  chmod +x "$start_script"
}

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE SECRET KEY
# ─────────────────────────────────────────────────────────────────────────────

step "Generating secure secret key"

if [[ -n "$WEBUI_SECRET_KEY" ]]; then
  info "Using custom WEBUI_SECRET_KEY from environment variable."
else
  WEBUI_SECRET_KEY="$(openssl rand -hex 32)"
  success "Generated new random secret key (first 8 chars: ${WEBUI_SECRET_KEY:0:8}...)."
fi

# Store secret in .env file for security (not in docker-compose.yml)
ENV_FILE="${PROJECT_DIR}/.env"
_generate_env_file "$ENV_FILE"
success "Secret key stored securely in .env file (mode: 600)."

# ─────────────────────────────────────────────────────────────────────────────
# CREATE PROJECT DIRECTORY
# ─────────────────────────────────────────────────────────────────────────────

step "Creating project directory at ${PROJECT_DIR}"

if [[ ! -d "$PROJECT_DIR" ]]; then
  sudo mkdir -p "$PROJECT_DIR"
  sudo chown "${USER}:${USER}" "$PROJECT_DIR"
fi
cd "$PROJECT_DIR"

success "Directory ready."

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE DOCKER COMPOSE FILE
# ─────────────────────────────────────────────────────────────────────────────

step "Generating ${COMPOSE_FILE}"
_generate_compose_file "$COMPOSE_FILE"
success "docker-compose.yml created."

# ─────────────────────────────────────────────────────────────────────────────
# CREATE START SCRIPT
# ─────────────────────────────────────────────────────────────────────────────

step "Creating start script"
_generate_start_script "${PROJECT_DIR}/start_openwebui.sh"
success "start_openwebui.sh created."

# ─────────────────────────────────────────────────────────────────────────────
# PULL IMAGES
# ─────────────────────────────────────────────────────────────────────────────

step "Pulling Docker images"

docker compose pull

success "Images pulled."

# ─────────────────────────────────────────────────────────────────────────────
# START THE STACK
# ─────────────────────────────────────────────────────────────────────────────

step "Starting Open WebUI stack (detached)"

docker compose up -d

success "Stack started."

# ─────────────────────────────────────────────────────────────────────────────
# WAIT FOR OPENWEBUI TO BECOME AVAILABLE
# ─────────────────────────────────────────────────────────────────────────────

step "Waiting for Open WebUI to respond"

MAX_WAIT=120
INTERVAL=5
ELAPSED=0
READY=false

if [[ "$OPENWEBUI_TRAEFIK" == "true" ]]; then
  # Traefik mode: skip direct health check (TLS via domain)
  info "Traefik mode: skipping direct health check (TLS access at https://${OPENWEBUI_DOMAIN})"
  info "Container will be accessible once DNS resolves and TLS is provisioned"
  READY=true
else
  # Direct mode: check localhost:port
  ACCESS_URL="http://localhost:${OPENWEBUI_PORT}"
  
  while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "$ACCESS_URL" | grep -qE "^(200|302|303)"; then
      READY=true
      break
    fi
    echo -ne "\r    Waited ${ELAPSED}s / ${MAX_WAIT}s ..."
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  
  echo ""
fi

if [[ "$READY" == "true" ]]; then
  success "Open WebUI is up and responding!"
else
  warn "Open WebUI did not respond within ${MAX_WAIT}s."
  warn "It may still be starting. Check logs with:"
  warn "  docker compose logs -f"
fi

# Disable cleanup trap on successful completion
trap - EXIT

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Open WebUI setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

if [[ "$OPENWEBUI_TRAEFIK" == "true" ]]; then
  echo -e "  ${BOLD}Web UI (Traefik)${RESET}   https://${OPENWEBUI_DOMAIN}"
  echo -e "  ${BOLD}TLS${RESET}                Enabled via Let's Encrypt"
else
  echo -e "  ${BOLD}Web UI${RESET}             http://localhost:${OPENWEBUI_PORT}"
fi

echo ""
echo -e "  ${BOLD}LM Studio API${RESET}      http://localhost:${LM_STUDIO_PORT}/v1"
echo -e "  ${BOLD}Data directory${RESET}     Persistent volume (openwebui_data)"
echo -e "  ${BOLD}Compose file${RESET}       ${COMPOSE_FILE}"
echo -e "  ${BOLD}Environment file${RESET}   ${PROJECT_DIR}/.env"

echo ""
echo -e "${YELLOW}  First-time setup:${RESET}"
echo -e "  Open the Web UI and create your admin account."
echo -e "  The secret key has been auto-generated and stored in .env file."

if [[ "$OPENWEBUI_TRAEFIK" != "true" ]]; then
  echo ""
  echo -e "${YELLOW}  Note:${RESET}"
  echo -e "  - WEBUI_SECRET_KEY is securely generated and stored in .env file (not docker-compose.yml)"
  echo -e "  - To use a custom key, set WEBUI_SECRET_KEY env var before running this script"
fi

echo ""
echo -e "${BOLD}Useful commands:${RESET}"

if [[ "$OPENWEBUI_TRAEFIK" == "true" ]]; then
  echo -e "  ${CYAN}# Traefik-specific debug commands${RESET}"
  echo -e "  Check access logs:  docker logs traefik | grep \${OPENWEBUI_DOMAIN}"
  echo -e "  Verify DNS       :  dig \${OPENWEBUI_DOMAIN}"
  echo ""
fi

echo -e "  Start:        ./start_openwebui.sh"
echo -e "  Stop:         docker compose down"
echo -e "  Restart:      docker compose restart"
echo -e "  Follow logs:  docker compose logs -f"
echo -e "  Shell into:   docker exec -it openwebui bash"

if [[ "$OPENWEBUI_TRAEFIK" != "true" ]]; then
  echo ""
  echo -e "${BOLD}🔐 Security Notice:${RESET}"
  echo -e "  Your WEBUI_SECRET_KEY is stored in .env file (mode: 600)."
  echo -e "  Do not share this file or expose it publicly without TLS protection."
fi

echo ""
info "LM Studio must be running before starting Open WebUI. Start it with 'lmstudio' command from terminal."
