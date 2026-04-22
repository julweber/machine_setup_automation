#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-sshd.sh — Configure SSH server
# =============================================================================
#
# Description:
#   Installs and configures OpenSSH server with security-hardened settings.
#   Sets up public key authentication only and configures a custom port.
#
# Environment Variables (optional):
#   SSHD_PORT - SSH daemon port (default: 2224)
#
# Usage:
#   ./setup-sshd.sh
#   SSHD_PORT=2224 ./setup-sshd.sh
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
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

# Configuration lines to ensure are present
declare -a SSHD_CONFIG_LINES=(
    "PubkeyAuthentication yes"
    "PasswordAuthentication no"
    "Port ${SSHD_PORT}"
)

# =============================================================================
# Main
# =============================================================================

step "Setting up SSH server (port: ${SSHD_PORT})"

# Install OpenSSH server
step "Installing openssh-server"
sudo apt update
sudo apt install -y openssh-server

# Show SSH status
step "SSHD current status"
sudo systemctl status sshd --no-pager || true

# Check and append configuration lines
step "Configuring sshd"
for line in "${SSHD_CONFIG_LINES[@]}"; do
    if sudo grep -q "^${line}$" "${SSHD_CONFIG_FILE}"; then
        info "'${line}' already present in ${SSHD_CONFIG_FILE}"
    else
        info "Adding: ${line}"
        echo "${line}" | sudo tee -a "${SSHD_CONFIG_FILE}" > /dev/null
    fi
done

# Show final config
info "sshd configuration at: ${SSHD_CONFIG_FILE}"
sudo cat "${SSHD_CONFIG_FILE}"

# Enable and restart SSH
step "Restarting SSH service"
sudo systemctl enable --now ssh
sudo systemctl restart ssh

# Prepare .ssh directory
step "Preparing ~/.ssh directory"
mkdir -p "${HOME}/.ssh"
if [[ ! -f "${HOME}/.ssh/authorized_keys" ]]; then
    touch "${HOME}/.ssh/authorized_keys"
    info "Created new authorized_keys file"
else
    info "Existing authorized_keys preserved"
fi

success "SSH server configured successfully"
info "Place your public keys in: ${HOME}/.ssh/authorized_keys"
info "Connect with: ssh -p ${SSHD_PORT} $(whoami)@$(hostname -I | awk '{print $1}')"