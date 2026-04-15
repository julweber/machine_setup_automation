#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# configure-firewall.sh — Configure UFW firewall rules
# =============================================================================
#
# Description:
#   Configures UFW (Uncomplicated Firewall) rules for a development machine.
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

add_ufw_rule() {
  local port="$1"
  local description="$2"

  # Check if rule already exists
  if sudo ufw status numbered | grep -q "\[${port}\]"; then
    info "Rule for ${description} (${port}) already exists"
  else
    step "Adding rule for ${description} (${port})"
    sudo ufw allow "${port}" comment "${description}"
    sudo ufw allow "${port}/tcp" comment "${description}"
  fi
}

# =============================================================================
# Main
# =============================================================================

step "Configuring UFW firewall"

# Check prerequisites
if ! command -v ufw &>/dev/null; then
  error "UFW is not installed. Please install ufw first."
fi

info "Current configuration:"
echo "  SSHD_PORT=${SSHD_PORT}"
echo "  LM_STUDIO_PORT=${LM_STUDIO_PORT}"
echo "  OPENCODE_PORT=${OPENCODE_PORT}"
echo "  OPENWEBUI_PORT=${OPENWEBUI_PORT}"
echo "  KUBERNETES_API_PORT=${KUBERNETES_API_PORT}"
echo "  GNOME_REMOTE_PORT=${GNOME_REMOTE_PORT}"

# Show current status
step "Current firewall status"
sudo ufw status

step "Current configured rules"
sudo ufw show added || true

# Add firewall rules
add_ufw_rule "${SSHD_PORT}" "SSHD"
add_ufw_rule "${LM_STUDIO_PORT}" "LM_STUDIO"
add_ufw_rule "${OPENCODE_PORT}" "OPENCODE"

# Optional services (commented out by default)
# Uncomment to enable:
# add_ufw_rule "${OPENWEBUI_PORT}" "OPENWEBUI"
# add_ufw_rule "${KUBERNETES_API_PORT}" "KUBERNETES_API"
# add_ufw_rule "${GNOME_REMOTE_PORT}" "GNOME_REMOTE"

# Enable firewall
step "Enabling firewall"
sudo ufw enable

# Show final status
step "Final firewall status"
sudo ufw status

success "Firewall configured successfully"