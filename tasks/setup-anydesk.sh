#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-anydesk.sh — Install AnyDesk remote desktop application
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
: "${ANYDESK_KEY_PATH:="/etc/apt/keyrings/keys.anydesk.com.asc"}"
: "${ANYDESK_LIST_PATH:="/etc/apt/sources.list.d/anydesk-stable.list"}"
ANYDESK_APT_KEY="https://keys.anydesk.com/repos/DEB-GPG-KEY"

# =============================================================================
# Main
# =============================================================================

step "Setting up AnyDesk repository"

# Check if AnyDesk is already installed
if command -v anydesk &>/dev/null; then
  success "AnyDesk is already installed: $(anydesk --version 2>/dev/null | head -n1 || echo 'unknown version')"
  exit 0
fi

info "Installing AnyDesk..."

# Install prerequisites
step "Installing prerequisites (ca-certificates, curl, apt-transport-https)"
sudo apt update
sudo apt install -y ca-certificates curl apt-transport-https

# Create keyrings directory and download GPG key
step "Downloading AnyDesk GPG key"
sudo install -m 0755 -d /etc/apt/keyrings
if [[ -f "${ANYDESK_KEY_PATH}" ]]; then
  info "GPG key already exists at ${ANYDESK_KEY_PATH}, skipping download"
else
  sudo curl -fsSL "${ANYDESK_APT_KEY}" -o "${ANYDESK_KEY_PATH}"
  sudo chmod a+r "${ANYDESK_KEY_PATH}"
fi

# Add repository
step "Adding AnyDesk repository"
echo "deb [signed-by=${ANYDESK_KEY_PATH}] https://deb.anydesk.com all main" | sudo tee "${ANYDESK_LIST_PATH}" > /dev/null

# Install AnyDesk
step "Installing AnyDesk package"
sudo apt update
sudo apt install -y anydesk

success "AnyDesk installed successfully"
info "Run 'anydesk' to start the application"