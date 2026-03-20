#!/usr/bin/env bash
# =============================================================================
# Excalidraw Docker Setup Script
# =============================================================================
#
# DESCRIPTION:
#   Automated setup script for deploying Excalidraw, a virtual whiteboard for
#   sketching hand-drawn like diagrams, using Docker. Supports direct host port
#   access or Traefik reverse-proxy integration with TLS termination.
#
# PREREQUISITES FOR TRAEFIK MODE:
#   When using EXCALIDRAW_TRAEFIK=true, the following must be configured:
#   1. Running Traefik instance connected to a Docker network (default: "proxy")
#      - The proxy network must exist and be accessible from this container
#      - Custom network can be specified via PROXY_NETWORK variable
#   2. DNS entry pointing to this server's IP address for EXCALIDRAW_DOMAIN
#      - A-record must resolve the domain to the host running Traefik
#      - Subdomain example: whiteboard.example.com
#   3. Port 443 available on the host for Let's Encrypt TLS
#      - Required for automatic SSL certificate provisioning via Traefik
#      - Ensure firewall allows inbound HTTPS traffic on port 443
#
# KEY ACTIONS:
#   1. Pre-flight checks: Verifies Docker installation & daemon
#   2. Checks if an Excalidraw container is already running (with prompt)
#   3. Pulls the latest Excalidraw Docker image from Docker Hub
#   4. Creates and starts a new container with auto-restart policy
#   5. Supports Traefik integration for domain-based access with TLS
#   6. Waits for container initialization and verifies it's running
#   7. Displays access information and useful management commands
#
# IMPORTANT VARIABLES:
#   HOST_PORT            - Host port for direct access (default: 5005)
#   EXCALIDRAW_IMAGE     - Docker image tag to use (default: excalidraw/excalidraw:latest)
#   CONTAINER_NAME       - Container name (default: excalidraw)
#   EXCALIDRAW_TRAEFIK   - Set to "true" to enable Traefik labels (default: false)
#   EXCALIDRAW_DOMAIN    - Domain for Traefik routing (required when EXCALIDRAW_TRAEFIK=true)
#   PROXY_NETWORK        - Traefik's external Docker network name (default: proxy)
#
# DEPENDENCIES:
#   - Docker: Must be installed and daemon must be running
#   - curl: Used for health check polling
#
# OUTPUTS:
#   - Running Excalidraw container with auto-restart policy
#
# USAGE:
#   sudo ./setup-excalidraw.sh
#   
#   # Or with custom configuration:
#   HOST_PORT=8080 sudo ./setup-excalidraw.sh
#
#   # With Traefik integration:
#   EXCALIDRAW_TRAEFIK=true EXCALIDRAW_DOMAIN=whiteboard.example.com sudo ./setup-excalidraw.sh
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running
# ─────────────────────────────────────────────────────────────────────────────

HOST_PORT="${HOST_PORT:-5005}"                  # Host port for direct access
EXCALIDRAW_IMAGE="${EXCALIDRAW_IMAGE:-excalidraw/excalidraw:latest}"  # Docker image to use
CONTAINER_NAME="${CONTAINER_NAME:-excalidraw}"

# Traefik reverse-proxy integration (opt-in)
EXCALIDRAW_TRAEFIK="${EXCALIDRAW_TRAEFIK:-false}"            # Set to "true" to enable Traefik labels
EXCALIDRAW_DOMAIN="${EXCALIDRAW_DOMAIN:-}"                   # e.g. whiteboard.example.com (required when EXCALIDRAW_TRAEFIK=true)
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"                      # Traefik's external Docker network name

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

# Trap for error handling
trap 'info "Setup failed. Check container state with: docker ps -a"' ERR

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
if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/helpers.sh"
  ensure_proxy_network
  if [[ -z "$EXCALIDRAW_DOMAIN" ]]; then
    error "EXCALIDRAW_DOMAIN must be set when EXCALIDRAW_TRAEFIK=true."
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK FOR EXISTING CONTAINER
# ─────────────────────────────────────────────────────────────────────────────

step "Checking for existing Excalidraw container"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  warn "Excalidraw container is already running."
  read -rp "    Stop and re-create the container? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    info "Stopping and removing existing container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    success "Existing container removed."
  else
    info "Keeping existing container. Exiting."
    exit 0
  fi
elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  # Container exists but is not running
  warn "Excalidraw container exists but is not running."
  read -rp "    Start existing container? [Y/n] " answer
  if [[ "${answer,,}" != "n" ]]; then
    info "Starting existing container..."
    docker start "$CONTAINER_NAME"
    success "Container started."
    # Skip to health check section
    step "Verifying Excalidraw is responding"
    
    if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
      # Traefik mode: skip direct health check
      info "Traefik mode: skipping direct health check (TLS access at https://${EXCALIDRAW_DOMAIN})"
      info "Container will be accessible once DNS resolves and TLS is provisioned"
      
      success "Excalidraw container started!"
    else
      # Direct mode: check localhost:port
      MAX_WAIT=60
      INTERVAL=5
      ELAPSED=0
      READY=false
      
      ACCESS_URL="http://localhost:${HOST_PORT}"
      
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
      
      if [[ "$READY" == "true" ]]; then
        success "Excalidraw is responding!"
      else
        warn "Excalidraw did not respond within ${MAX_WAIT}s."
        warn "It may still be starting. Check logs with:"
        warn "  docker logs -f ${CONTAINER_NAME}"
      fi
    fi
    
    # Jump to summary (exit early from this branch)
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  Excalidraw setup complete!${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
    echo ""
    
    if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
      echo -e "  ${BOLD}Web UI (Traefik)${RESET}   https://${EXCALIDRAW_DOMAIN}"
      echo -e "  ${BOLD}TLS${RESET}                Enabled via Let's Encrypt"
    else
      echo -e "  ${BOLD}Web UI${RESET}             http://localhost:${HOST_PORT}"
    fi
    
    echo ""
    echo -e "${YELLOW}  Notes:${RESET}"
    if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
      echo -e "  - Ensure your DNS points to this server's IP address"
      echo -e "  - TLS certificate will be auto-provisioned by Traefik"
    else
      echo -e "  - Access Excalidraw at http://localhost:${HOST_PORT}"
      echo -e "  - To expose externally, configure your own reverse proxy"
    fi
    
    echo ""
    echo -e "${BOLD}Useful commands:${RESET}"
    if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
      echo -e "  ${CYAN}# Traefik-specific debug commands${RESET}"
      echo -e "  Check access logs:  docker logs traefik | grep \${EXCALIDRAW_DOMAIN}"
      echo -e "  Verify DNS       :  dig \${EXCALIDRAW_DOMAIN}"
      echo ""
    fi
    echo -e "  Follow logs    :  docker logs -f ${CONTAINER_NAME}"
    echo -e "  Stop container :  docker stop ${CONTAINER_NAME}"
    echo -e "  Start container:  docker start ${CONTAINER_NAME}"
    echo -e "  Restart        :  docker restart ${CONTAINER_NAME}"
    echo -e "  Shell into     :  docker exec -it ${CONTAINER_NAME} sh"
    echo -e "  Remove         :  docker rm -f ${CONTAINER_NAME}"
    echo ""
    exit 0
  else
    info "Keeping container stopped. Exiting."
    exit 0
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# PORT CONFLICT CHECK (direct mode only)
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$EXCALIDRAW_TRAEFIK" != "true" ]]; then
  # Check if port is already in use
  if command -v ss &>/dev/null; then
    if ss -tuln 2>/dev/null | grep -q ":${HOST_PORT} "; then
      warn "Port ${HOST_PORT} appears to be in use."
      warn "Check what's using it with: sudo lsof -i :${HOST_PORT}"
      read -rp "    Continue anyway? [y/N] " answer
      if [[ "${answer,,}" != "y" ]]; then
        info "Aborted. Change HOST_PORT or free up the port and try again."
        exit 0
      fi
    fi
  elif command -v netstat &>/dev/null; then
    if netstat -tuln 2>/dev/null | grep -q ":${HOST_PORT} "; then
      warn "Port ${HOST_PORT} appears to be in use."
      warn "Check what's using it with: sudo lsof -i :${HOST_PORT}"
      read -rp "    Continue anyway? [y/N] " answer
      if [[ "${answer,,}" != "y" ]]; then
        info "Aborted. Change HOST_PORT or free up the port and try again."
        exit 0
      fi
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# PULL DOCKER IMAGE
# ─────────────────────────────────────────────────────────────────────────────

step "Pulling Excalidraw Docker image"

if ! docker pull "$EXCALIDRAW_IMAGE"; then
  error "Failed to pull Docker image '$EXCALIDRAW_IMAGE'. Check your network connection and verify the image name is correct on Docker Hub."
fi
success "Image pulled."

# ─────────────────────────────────────────────────────────────────────────────
# START CONTAINER
# ─────────────────────────────────────────────────────────────────────────────

step "Starting Excalidraw container"

if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
  # Traefik mode: connect to proxy network, no host port binding
  info "Configuring for Traefik reverse-proxy access at https://${EXCALIDRAW_DOMAIN}"
  
  docker run -dit \
    --name "$CONTAINER_NAME" \
    --restart always \
    --network "$PROXY_NETWORK" \
    --label "traefik.enable=true" \
    --label "traefik.docker.network=${PROXY_NETWORK}" \
    --label "traefik.http.routers.excalidraw.rule=Host(\`${EXCALIDRAW_DOMAIN}\`)" \
    --label "traefik.http.routers.excalidraw.entrypoints=websecure" \
    --label "traefik.http.routers.excalidraw.tls.certresolver=letsencrypt" \
    --label "traefik.http.services.excalidraw.loadbalancer.server.port=80" \
    "$EXCALIDRAW_IMAGE"
  
  success "Container started with Traefik integration."
else
  # Direct access mode: bind host port
  info "Configuring for direct host access on port ${HOST_PORT}"
  
  docker run -dit \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${HOST_PORT}:80" \
    "$EXCALIDRAW_IMAGE"
  
  success "Container started with direct access."
fi

# ─────────────────────────────────────────────────────────────────────────────
# WAIT FOR CONTAINER TO BE READY
# ─────────────────────────────────────────────────────────────────────────────

step "Waiting for Excalidraw to start"

sleep 3

# Verify the container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  success "Container is running."
else
  warn "Excalidraw container may not be running as expected."
  info "Last 50 lines of container logs:"
  docker logs --tail 50 "$CONTAINER_NAME" 2>&1 || true
  error "Check the logs above for errors. To follow logs in real-time: docker logs -f ${CONTAINER_NAME}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH CHECK
# ─────────────────────────────────────────────────────────────────────────────

step "Verifying Excalidraw is responding"

MAX_WAIT=60
INTERVAL=5
ELAPSED=0
READY=false

if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
  # Traefik mode: no direct port binding, skip health check
  info "Traefik mode: skipping direct health check (TLS access at https://${EXCALIDRAW_DOMAIN})"
  info "Container will be accessible once DNS resolves and TLS is provisioned"
  READY=true
else
  # Direct mode: check localhost:port
  ACCESS_URL="http://localhost:${HOST_PORT}"
  
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
  success "Excalidraw is responding!"
else
  warn "Excalidraw did not respond within ${MAX_WAIT}s."
  warn "It may still be starting. Check logs with:"
  warn "  docker logs -f ${CONTAINER_NAME}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Excalidraw setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
  echo -e "  ${BOLD}Web UI (Traefik)${RESET}   https://${EXCALIDRAW_DOMAIN}"
  echo -e "  ${BOLD}TLS${RESET}                Enabled via Let's Encrypt"
else
  echo -e "  ${BOLD}Web UI${RESET}             http://localhost:${HOST_PORT}"
fi

echo ""
echo -e "${YELLOW}  Notes:${RESET}"
if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
  echo -e "  - Ensure your DNS points to this server's IP address"
  echo -e "  - TLS certificate will be auto-provisioned by Traefik"
else
  echo -e "  - Access Excalidraw at http://localhost:${HOST_PORT}"
  echo -e "  - To expose externally, configure your own reverse proxy"
fi

echo ""
echo -e "${BOLD}Useful commands:${RESET}"
if [[ "$EXCALIDRAW_TRAEFIK" == "true" ]]; then
  echo -e "  ${CYAN}# Traefik-specific debug commands${RESET}"
  echo -e "  Check access logs:  docker logs traefik | grep \${EXCALIDRAW_DOMAIN}"
  echo -e "  Verify DNS       :  dig \${EXCALIDRAW_DOMAIN}"
  echo ""
fi
echo -e "  Follow logs    :  docker logs -f ${CONTAINER_NAME}"
echo -e "  Stop container :  docker stop ${CONTAINER_NAME}"
echo -e "  Start container:  docker start ${CONTAINER_NAME}"
echo -e "  Restart        :  docker restart ${CONTAINER_NAME}"
echo -e "  Shell into     :  docker exec -it ${CONTAINER_NAME} sh"
echo -e "  Remove         :  docker rm -f ${CONTAINER_NAME}"
echo ""
