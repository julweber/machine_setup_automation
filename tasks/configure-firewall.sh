#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# configure-firewall.sh — Configure UFW firewall rules
# =============================================================================
#
# Description:
#   Configures UFW (Uncomplicated Firewall) rules for a development machine.
#
#   Uses sudo internally for privileged operations. Assumes default-deny policy.
#
#   IMPORTANT: When running over SSH, ensure SSHD_PORT is correct before
#   enabling the firewall to avoid remote lockout.
#
# Environment Variables (optional):
#   SSHD_PORT (default: 2224)
#   LM_STUDIO_PORT (default: 1234)
#   OPENCODE_PORT (default: 4096)
#   Additional ports can be enabled by setting their respective variables
#
# Usage:
#   ./configure-firewall.sh
#   SSHD_PORT=2224 LM_STUDIO_PORT=1234 ./configure-firewall.sh
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

# Configuration
: "${SSHD_PORT:=2224}"
: "${LM_STUDIO_PORT:=1234}"
: "${OPENCODE_PORT:=4096}"
: "${OPENWEBUI_PORT:=3333}"
: "${KUBERNETES_API_PORT:=6443}"
: "${GNOME_REMOTE_PORT:=3389}"

# =============================================================================
# Helper functions
# =============================================================================

validate_port() {
  local port="$1"
  local name="$2"
  if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    error "${name}='${port}' is not a valid port number (must be 1-65535)"
    exit 1
  fi
}

# =============================================================================
# Main
# =============================================================================

step "Configuring UFW firewall"

# Check prerequisites
if ! ufw_available; then
  error "UFW is not installed. Please install ufw first."
fi

info "Current configuration:"
echo "  SSHD_PORT=${SSHD_PORT}"
echo "  LM_STUDIO_PORT=${LM_STUDIO_PORT}"
echo "  OPENCODE_PORT=${OPENCODE_PORT}"
echo "  OPENWEBUI_PORT=${OPENWEBUI_PORT}"
echo "  KUBERNETES_API_PORT=${KUBERNETES_API_PORT}"
echo "  GNOME_REMOTE_PORT=${GNOME_REMOTE_PORT}"

# Validate ports
validate_port "${SSHD_PORT}" "SSHD_PORT"
validate_port "${LM_STUDIO_PORT}" "LM_STUDIO_PORT"
validate_port "${OPENCODE_PORT}" "OPENCODE_PORT"

# Show current status
step "Current firewall status"
ufw_show_status

step "Current configured rules"
sudo ufw show added || true

# Add SSH rule FIRST to prevent lockout
ufw_add_rule "${SSHD_PORT}" "tcp" "SSHD"

# Add remaining service rules
ufw_add_rule "${LM_STUDIO_PORT}" "tcp" "LM_STUDIO"
ufw_add_rule "${OPENCODE_PORT}" "tcp" "OPENCODE"

# Optional services (commented out by default)
# Uncomment to enable:
# validate_port "${OPENWEBUI_PORT}" "OPENWEBUI_PORT"
# ufw_add_rule "${OPENWEBUI_PORT}" "tcp" "OPENWEBUI"
# validate_port "${KUBERNETES_API_PORT}" "KUBERNETES_API_PORT"
# ufw_add_rule "${KUBERNETES_API_PORT}" "tcp" "KUBERNETES_API"
# validate_port "${GNOME_REMOTE_PORT}" "GNOME_REMOTE_PORT"
# ufw_add_rule "${GNOME_REMOTE_PORT}" "tcp" "GNOME_REMOTE"

# Enable firewall (non-interactive, prevents lockout)
step "Enabling firewall"
ufw_enable

# Show final status
step "Final firewall status"
ufw_show_status

success "Firewall configured successfully"
