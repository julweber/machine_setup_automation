#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-opencode-server.sh — Install Opencode AI Coding Agent Server
# =============================================================================
#
# Description:
#   Installs Opencode AI Coding Agent Server in Docker or systemd mode.
#
# Environment Variables (optional):
#   OPENCODE_PORT            - Server port (default: 4096)
#   OPENCODE_HOSTNAME        - Bind address (default: 0.0.0.0)
#   OPENCODE_SERVER_USERNAME - Auth username (default: admin)
#   OPENCODE_SERVER_PASSWORD - Auth password (auto-generated if empty)
#   USE_DOCKER               - Use Docker mode (default: false)
#   OPENCODE_DATA_DIR        - Data directory (default: /srv/opencode)
#   OPENCODE_TRAEFIK         - Enable Traefik (default: false)
#
# Usage:
#   ./setup-opencode-server.sh
#   USE_DOCKER=true ./setup-opencode-server.sh
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
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

# Logging functions (info, success, warn, error, step) are provided by lib/helpers.sh

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

load_config() {
    OPENCODE_PORT="${OPENCODE_PORT:-4096}"
    OPENCODE_HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"
    OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-admin}"
    OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"
    USE_DOCKER="${USE_DOCKER:-false}"
    DATA_DIR="${OPENCODE_DATA_DIR:-/srv/opencode}"
    OPENCODE_TRAEFIK="${OPENCODE_TRAEFIK:-false}"
    PROXY_NETWORK="${PROXY_NETWORK:-proxy}"
    OPENCODE_DOMAIN="${OPENCODE_DOMAIN:-}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

print_config() {
    local mode
    mode="$(if [[ "$USE_DOCKER" == "true" ]]; then echo "docker"; else echo "systemd"; fi)"

    echo "Opencode Server Configuration:"
    echo "  Mode:                     $mode"
    echo "  OPENCODE_PORT:            $OPENCODE_PORT"
    echo "  OPENCODE_HOSTNAME:        $OPENCODE_HOSTNAME"
    echo "  OPENCODE_SERVER_USERNAME: $OPENCODE_SERVER_USERNAME"
    echo "  OPENCODE_SERVER_PASSWORD: ${OPENCODE_SERVER_PASSWORD:+*** (set)}"
    if [[ "$USE_DOCKER" == "true" ]]; then
        echo "  DATA_DIR:                 $DATA_DIR"
        if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
            echo "  OPENCODE_DOMAIN:          ${OPENCODE_DOMAIN:-(required for Traefik)}"
            echo "  PROXY_NETWORK:            $PROXY_NETWORK"
        fi
    fi
    echo "--------------------------------"
}

maybe_generate_password() {
    if [[ -n "$OPENCODE_SERVER_PASSWORD" ]]; then
        return
    fi

    step "Generating secure random password..."
    OPENCODE_SERVER_PASSWORD=$(openssl rand -base64 32)

    echo ""
    echo "=============================================="
    echo "IMPORTANT: Generated Opencode Server Password"
    echo "=============================================="
    echo ""
    echo "Username: $OPENCODE_SERVER_USERNAME"
    echo "Password: $OPENCODE_SERVER_PASSWORD"
    echo ""
    echo "Please save this password securely. It will not be displayed again."
    echo "You can set OPENCODE_SERVER_PASSWORD environment variable to reuse it."
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

preflight_docker() {
    step "Running pre-flight checks (Docker mode)"

    if ! command -v docker &>/dev/null; then
        error "Docker is not installed or not in PATH. Run setup-docker.sh first."
    fi

    if ! docker info &>/dev/null; then
        error "Docker daemon is not running. Start it with: sudo systemctl start docker"
    fi

    success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

    if [[ -z "$OPENCODE_SERVER_PASSWORD" ]] && ! command -v openssl &>/dev/null; then
        error "openssl is not installed. Required for generating secure password. Install it or set OPENCODE_SERVER_PASSWORD manually."
    fi

    if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        _preflight_traefik
    fi
}

_preflight_traefik() {
    if ! ensure_proxy_network; then
        warn "Traefik proxy network '${PROXY_NETWORK}' not found or inaccessible."
        warn "If you want Traefik integration, run setup-traefik.sh first."
        warn "Continuing in direct-access mode..."
        OPENCODE_TRAEFIK="false"
        return
    fi

    if [[ -z "$OPENCODE_DOMAIN" ]]; then
        error "OPENCODE_DOMAIN must be set when OPENCODE_TRAEFIK=true (e.g., opencode.example.com)."
    fi
}

preflight_systemd() {
    step "Running pre-flight checks (systemd mode)"

    if ! command -v sudo &>/dev/null; then
        error "sudo is not installed."
    fi

    if [[ -z "$OPENCODE_SERVER_PASSWORD" ]] && ! command -v openssl &>/dev/null; then
        warn "openssl not found. Generating password may fail, or set OPENCODE_SERVER_PASSWORD manually."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# SHARED: INSTALL OPENCODE VIA NPM
# ─────────────────────────────────────────────────────────────────────────────

install_opencode_npm() {
    step "Installing/Updating Opencode Server..."

    if ! command -v npm &>/dev/null; then
        info "npm is not installed. Installing Node.js and npm..."
        sudo apt update
        sudo apt install -y nodejs npm
    fi

    if command -v opencode &>/dev/null; then
        info "Opencode CLI already installed at $(which opencode). Updating to latest version..."
    else
        info "Installing opencode globally via npm..."
    fi

    sudo npm install -g opencode-ai --force

    if ! opencode --version &>/dev/null; then
        warn "Opencode CLI installation verification failed, but continuing..."
    fi

    success "Opencode CLI installed/updated successfully."
}

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER MODE
# ─────────────────────────────────────────────────────────────────────────────

_generate_compose_file() {
    local compose_file="$1"

    sudo tee "$compose_file" > /dev/null << EOF
# Opencode Server Docker Compose Configuration
# Generated: $(date -Iseconds)

networks:
  opencode:
    external: false
EOF

    if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        sudo tee -a "$compose_file" > /dev/null << EOF
  ${PROXY_NETWORK}:
    external: true
EOF
    fi

    sudo tee -a "$compose_file" > /dev/null << EOF

services:
  opencode:
    image: ghcr.io/anomalyco/opencode:latest
    container_name: opencode-agent
    restart: unless-stopped
    env_file:
      - .env
    command: ["serve", "--hostname", "0.0.0.0", "--port", "4096"]
EOF

    if [[ "$OPENCODE_TRAEFIK" != "true" ]]; then
        sudo tee -a "$compose_file" > /dev/null << EOF
    ports:
      - "${OPENCODE_PORT}:4096"
EOF
    fi

    if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        sudo tee -a "$compose_file" > /dev/null << EOF
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=${PROXY_NETWORK}"
      - "traefik.http.routers.opencode.rule=Host(\`${OPENCODE_DOMAIN}\`)"
      - "traefik.http.routers.opencode.entrypoints=websecure"
      - "traefik.http.routers.opencode.tls=true"
      - "traefik.http.routers.opencode.tls.certresolver=letsencrypt"
      - "traefik.http.services.opencode.loadbalancer.server.port=4096"
EOF
    fi

    sudo tee -a "$compose_file" > /dev/null << EOF
    networks:
      - opencode
EOF

    if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        sudo tee -a "$compose_file" > /dev/null << EOF
      - ${PROXY_NETWORK}
EOF
    fi

    sudo tee -a "$compose_file" > /dev/null << EOF
    volumes:
      - opencode_data:/data

volumes:
  opencode_data:
EOF
}

_generate_env_file() {
    local env_file="${DATA_DIR}/.env"

    if [[ -f "$env_file" ]]; then
        warn "Existing .env file found. Backing up to ${env_file}.bak"
        sudo cp "$env_file" "${env_file}.bak"
    fi

    sudo tee "$env_file" > /dev/null << EOF
# Opencode Server Environment Variables
# This file contains sensitive credentials - keep it secure!
OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}
OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}
EOF

    sudo chmod 600 "$env_file"
    success "Secrets stored securely in .env file (mode: 600)."
}

_generate_start_script() {
    sudo tee "${DATA_DIR}/start_opencode.sh" > /dev/null << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
sudo docker compose up -d
EOF
    sudo chmod +x "${DATA_DIR}/start_opencode.sh"
    success "start_opencode.sh created."
}

_wait_for_opencode_docker() {
    step "Waiting for Opencode to respond"

    if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        info "Traefik mode: skipping direct health check (TLS access at https://${OPENCODE_DOMAIN})"
        info "Container will be accessible once DNS resolves and TLS is provisioned."
        return 0
    fi

    local access_url="http://localhost:${OPENCODE_PORT}"
    local max_wait=120 interval=5 elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "$access_url" | grep -qE "^(200|302|303|401)"; then
            echo ""
            success "Opencode is up and responding!"
            return 0
        fi
        echo -ne "\r    Waited ${elapsed}s / ${max_wait}s ..."
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo ""
    warn "Opencode did not respond within ${max_wait}s."
    warn "It may still be starting. Check logs with: docker compose logs -f"
}

_configure_ufw_docker() {
    if ! ufw_available || [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        return
    fi

    step "Configuring UFW firewall"
    if ! ufw_rule_exists "$OPENCODE_PORT"; then
        info "Adding firewall rule for port $OPENCODE_PORT..."
        ufw_add_rule "$OPENCODE_PORT" "tcp" "OPENCODE"
    fi
}

setup_docker() {
    local compose_file="${DATA_DIR}/docker-compose.yml"

    trap 'warn "Setup failed (exit code: $?)! Cleaning up..."; cd "$DATA_DIR" && sudo docker compose down --remove-orphans 2>/dev/null || true' EXIT

    sudo mkdir -p "$DATA_DIR"

    step "Generating ${compose_file}"
    _generate_compose_file "$compose_file"
    success "docker-compose.yml created."

    step "Generating ${DATA_DIR}/.env"
    _generate_env_file

    step "Creating start script"
    _generate_start_script

    step "Pulling Docker images"
    cd "$DATA_DIR"
    sudo docker compose pull
    success "Images pulled."

    step "Starting Opencode stack (detached)"
    sudo docker compose up -d
    success "Stack started."

    _wait_for_opencode_docker
    _configure_ufw_docker

    trap - EXIT
}

summary_docker() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  Opencode Server (Docker) setup complete!${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
    echo ""

    if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        echo -e "  ${BOLD}Web UI (Traefik)${RESET}   https://${OPENCODE_DOMAIN}"
        echo -e "  ${BOLD}TLS${RESET}                Enabled via Let's Encrypt"
    else
        echo -e "  ${BOLD}Web UI${RESET}             http://localhost:${OPENCODE_PORT}"
    fi

    echo ""
    echo -e "  ${BOLD}Data directory${RESET}     Persistent volume (opencode_data)"
    echo -e "  ${BOLD}Compose file${RESET}       ${DATA_DIR}/docker-compose.yml"
    echo -e "  ${BOLD}Environment file${RESET}   ${DATA_DIR}/.env"

    if [[ "$OPENCODE_TRAEFIK" != "true" ]]; then
        echo ""
        echo -e "${YELLOW}  Note:${RESET}"
        echo -e "  - OPENCODE_SERVER_PASSWORD is stored in .env (not exposed in docker-compose.yml)"
        echo -e "  - To use a custom password, set OPENCODE_SERVER_PASSWORD before running this script"
    fi

    if [[ "$OPENCODE_TRAEFIK" == "true" ]]; then
        echo ""
        echo -e "${BOLD}${CYAN}Traefik-specific commands:${RESET}"
        echo -e "  Check access logs:  docker logs traefik | grep ${OPENCODE_DOMAIN}"
        echo -e "  Verify DNS:         dig ${OPENCODE_DOMAIN}"
    fi

    echo ""
    echo -e "${BOLD}Useful commands:${RESET}"
    echo -e "  Start:        ./start_opencode.sh"
    echo -e "  Stop:         docker compose down"
    echo -e "  Restart:      docker compose restart"
    echo -e "  Follow logs:  docker compose logs -f"
    echo -e "  Shell into:   docker exec -it opencode-agent bash"

    if [[ "$OPENCODE_TRAEFIK" != "true" ]]; then
        echo ""
        echo -e "${BOLD}Security Notice:${RESET}"
        echo -e "  Your OPENCODE_SERVER_PASSWORD is stored in .env (mode: 600)."
        echo -e "  Do not share this file or expose it without TLS protection."
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEMD MODE
# ─────────────────────────────────────────────────────────────────────────────

_write_service_file() {
    local service_file="/etc/systemd/system/opencode-agent.service"

    if [[ -f "$service_file" ]]; then
        info "Service file $service_file already exists. Skipping write."
        return
    fi

    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Opencode AI Coding Agent Server
After=network.target

[Service]
Type=simple
User=$USER
Environment="OPENCODE_SERVER_USERNAME=$OPENCODE_SERVER_USERNAME"
Environment="OPENCODE_SERVER_PASSWORD=$OPENCODE_SERVER_PASSWORD"
ExecStart=/usr/local/bin/opencode serve --hostname ${OPENCODE_HOSTNAME} --port ${OPENCODE_PORT}
Restart=always
RestartSec=5
WorkingDirectory=$HOME

[Install]
WantedBy=multi-user.target
EOF
    success "Service file written to $service_file"
}

_configure_ufw_systemd() {
    if ! ufw_available; then
        return
    fi

    step "Configuring UFW firewall (systemd mode)"
    if ! ufw_rule_exists "$OPENCODE_PORT"; then
        info "Adding firewall rule for port $OPENCODE_PORT..."
        ufw_add_rule "$OPENCODE_PORT" "tcp" "OPENCODE"
    fi
}

_test_health_endpoint() {
    if [[ "$OPENCODE_HOSTNAME" == "127.0.0.1" || "$OPENCODE_HOSTNAME" == "localhost" ]]; then
        return
    fi

    info "Testing health endpoint..."
    sleep 3
    if command -v curl &>/dev/null; then
        curl -s --user "${OPENCODE_SERVER_USERNAME}:${OPENCODE_SERVER_PASSWORD}" \
            "http://$OPENCODE_HOSTNAME:$OPENCODE_PORT/global/health" || true
    fi
}

setup_systemd() {
    step "Creating systemd service file"
    _write_service_file

    step "Reloading systemd daemon"
    sudo systemctl daemon-reload
    success "Systemd daemon reloaded."

    step "Enabling opencode-agent.service"
    sudo systemctl enable opencode-agent.service
    success "Service enabled (will start on boot)."

    step "Starting/restarting opencode-agent.service"
    if sudo systemctl is-active --quiet opencode-agent.service; then
        info "Service is running. Restarting to apply changes..."
        sudo systemctl restart opencode-agent.service
    else
        info "Service not running. Starting..."
        sudo systemctl start opencode-agent.service
    fi
    success "Opencode service started/restarted successfully."

    _configure_ufw_systemd
    _test_health_endpoint
}

summary_systemd() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  Opencode Server (systemd) setup complete!${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "  ${BOLD}Web UI${RESET}   http://${OPENCODE_HOSTNAME}:${OPENCODE_PORT}"
    echo ""
    echo -e "${BOLD}${CYAN}Admin credentials:${RESET}"
    echo -e "  Username: $OPENCODE_SERVER_USERNAME"
    if [[ -n "$OPENCODE_SERVER_PASSWORD" ]]; then
        echo -e "  Password: *** (configured)"
    else
        echo -e "  Password: *** (auto-generated on first run via env vars)"
    fi

    echo ""
    echo -e "${BOLD}Useful commands:${RESET}"
    echo -e "  Status:       sudo systemctl status opencode-agent"
    echo -e "  Start:        sudo systemctl start opencode-agent"
    echo -e "  Stop:         sudo systemctl stop opencode-agent"
    echo -e "  Restart:      sudo systemctl restart opencode-agent"
    echo -e "  Logs:         sudo journalctl -u opencode-agent -f"

    echo ""
    echo -e "${BOLD}Security Notice:${RESET}"
    echo -e "  Environment variables are stored in the systemd service file."
    echo -e "  View with: sudo systemctl cat opencode-agent"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# UNINSTALL
# ─────────────────────────────────────────────────────────────────────────────

uninstall_docker() {
    step "Uninstalling Opencode Server (Docker mode)"

    if [[ -f "${DATA_DIR}/docker-compose.yml" ]]; then
        info "Stopping and removing Docker stack..."
        cd "$DATA_DIR"
        sudo docker compose down --remove-orphans
        success "Docker stack removed."
    else
        warn "No docker-compose.yml found in ${DATA_DIR}. Skipping stack teardown."
    fi

    if [[ -d "$DATA_DIR" ]]; then
        info "Removing data directory ${DATA_DIR}..."
        sudo rm -rf "$DATA_DIR"
        success "Data directory removed."
    fi

    if ufw_available && [[ "$OPENCODE_TRAEFIK" != "true" ]]; then
        step "Removing UFW firewall rule for port ${OPENCODE_PORT}"
        ufw_delete_rule "$OPENCODE_PORT" "tcp"
    fi

    success "Opencode Server (Docker) uninstalled."
}

uninstall_systemd() {
    local service_file="/etc/systemd/system/opencode-agent.service"

    step "Uninstalling Opencode Server (systemd mode)"

    if sudo systemctl is-active --quiet opencode-agent.service 2>/dev/null; then
        info "Stopping opencode-agent.service..."
        sudo systemctl stop opencode-agent.service
        success "Service stopped."
    fi

    if sudo systemctl is-enabled --quiet opencode-agent.service 2>/dev/null; then
        info "Disabling opencode-agent.service..."
        sudo systemctl disable opencode-agent.service
        success "Service disabled."
    fi

    if [[ -f "$service_file" ]]; then
        info "Removing service file ${service_file}..."
        sudo rm "$service_file"
        sudo systemctl daemon-reload
        success "Service file removed and daemon reloaded."
    else
        warn "Service file ${service_file} not found. Already removed?"
    fi

    if ufw_available; then
        step "Removing UFW firewall rule for port ${OPENCODE_PORT}"
        ufw_delete_rule "$OPENCODE_PORT" "tcp"
    fi

    success "Opencode Server (systemd) uninstalled."
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat << 'EOF'
Usage: setup-opencode-server.sh [--help] [--uninstall]

Installs and configures the Opencode AI Coding Agent Server.
All configuration is provided via environment variables.

GENERAL OPTIONS
  OPENCODE_PORT                Port to bind the server to.
                               Default: 4096
  OPENCODE_HOSTNAME            Hostname/IP to bind to.
                               Default: 0.0.0.0
  OPENCODE_SERVER_USERNAME     Username for HTTP basic auth.
                               Default: admin
  OPENCODE_SERVER_PASSWORD     Password for HTTP basic auth.
                               Default: auto-generated (printed once at startup)

DEPLOYMENT MODE
  USE_DOCKER                   Set to "true" to use Docker Compose deployment.
                               Default: false (systemd/npm mode)

DOCKER MODE OPTIONS            (only used when USE_DOCKER=true)
  OPENCODE_DATA_DIR            Host directory for Docker Compose files and .env.
                               Default: /srv/opencode

TRAEFIK OPTIONS                (only used when USE_DOCKER=true)
  OPENCODE_TRAEFIK             Set to "true" to enable Traefik reverse proxy integration.
                               Default: false
  OPENCODE_DOMAIN              Public domain name for Traefik routing.
                               Required when OPENCODE_TRAEFIK=true
                               Example: opencode.example.com
  PROXY_NETWORK                Name of the external Docker network Traefik listens on.
                               Default: proxy

EXAMPLES
  # Systemd mode with auto-generated password:
  sudo bash setup-opencode-server.sh

  # Systemd mode with explicit password:
  OPENCODE_SERVER_PASSWORD=mysecret sudo bash setup-opencode-server.sh

  # Docker mode with Traefik:
  USE_DOCKER=true OPENCODE_TRAEFIK=true OPENCODE_DOMAIN=opencode.example.com \
    sudo bash setup-opencode-server.sh

  # Docker mode, direct port binding:
  USE_DOCKER=true OPENCODE_PORT=4096 sudo bash setup-opencode-server.sh

  # Uninstall (systemd mode):
  sudo bash setup-opencode-server.sh --uninstall

  # Uninstall (Docker mode):
  USE_DOCKER=true sudo bash setup-opencode-server.sh --uninstall
EOF
}

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    load_config

    if [[ "${1:-}" == "--uninstall" ]]; then
        if [[ "$USE_DOCKER" == "true" ]]; then
            uninstall_docker
        else
            uninstall_systemd
        fi
        exit 0
    fi

    print_config
    maybe_generate_password

    if [[ "$USE_DOCKER" == "true" ]]; then
        preflight_docker
        setup_docker
        summary_docker
    else
        preflight_systemd
        install_opencode_npm
        setup_systemd
        summary_systemd
    fi
}

main "$@"
