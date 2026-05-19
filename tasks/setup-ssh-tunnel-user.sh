#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-ssh-tunnel-user.sh — Create restricted SSH tunnel user
# =============================================================================
#
# Description:
#   Creates a restricted SSH user account for secure tunnel-only access.
#   No interactive shell access, key-based auth only.
#
# Environment Variables (optional):
#   RESTRICTED_USER      - Username to create (default: tunneluser)
#   SSHD_PORT            - SSH port (default: 2224)
#   ALLOW_GATEWAY_PORTS  - Allow remote port forwarding (default: no)
#
# Usage:
#   RESTRICTED_USER=myuser source tasks/setup-ssh-tunnel-user.sh
#   ./setup-ssh-tunnel-user.sh
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
: "${RESTRICTED_USER:=tunneluser}"
: "${SSHD_PORT:=2224}"
: "${ALLOW_GATEWAY_PORTS:=no}"
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

# =============================================================================
# Main
# =============================================================================

step "Setting up restricted SSH tunnel user: ${RESTRICTED_USER}"

# Validate username
if [[ -z "${RESTRICTED_USER}" ]]; then
  error "RESTRICTED_USER environment variable must be set"
fi

if ! [[ "${RESTRICTED_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  error "Invalid username '${RESTRICTED_USER}'. Must start with lowercase letter/underscore."
fi

info "SSH Port: ${SSHD_PORT}"

# Check if user already exists (idempotent)
if id "${RESTRICTED_USER}" &>/dev/null; then
  success "User '${RESTRICTED_USER}' already exists. Skipping."
  exit 0
fi

# Create user
step "Creating user '${RESTRICTED_USER}'"
sudo useradd -m -s /usr/sbin/nologin "${RESTRICTED_USER}"
info "User created with nologin shell"

# Lock password
sudo passwd -l "${RESTRICTED_USER}" 2>/dev/null || true
info "Password authentication disabled"

# Setup SSH directory
RESTRICTED_HOME="/home/${RESTRICTED_USER}"
step "Configuring SSH directory"
sudo mkdir -p "${RESTRICTED_HOME}/.ssh"
sudo touch "${RESTRICTED_HOME}/.ssh/authorized_keys"
sudo chmod 700 "${RESTRICTED_HOME}/.ssh"
sudo chmod 600 "${RESTRICTED_HOME}/.ssh/authorized_keys"
sudo chown -R "${RESTRICTED_USER}:${RESTRICTED_USER}" "${RESTRICTED_HOME}/.ssh"

# Generate SSH keypair
step "Generating SSH key pair"
sudo -u "${RESTRICTED_USER}" ssh-keygen -t ed25519 \
  -f "${RESTRICTED_HOME}/.ssh/id_ed25519" \
  -N "" \
  -C "restricted-tunnel-user@${HOSTNAME}" \
  -q

# Set permissions
sudo chmod 600 "${RESTRICTED_HOME}/.ssh/id_ed25519"
sudo chown "${RESTRICTED_USER}:${RESTRICTED_USER}" "${RESTRICTED_HOME}/.ssh/id_ed25519"
sudo chown "${RESTRICTED_USER}:${RESTRICTED_USER}" "${RESTRICTED_HOME}/.ssh/id_ed25519.pub"

# Add public key to authorized_keys
PUBLIC_KEY=$(sudo cat "${RESTRICTED_HOME}/.ssh/id_ed25519.pub")
echo "${PUBLIC_KEY}" | sudo tee -a "${RESTRICTED_HOME}/.ssh/authorized_keys" > /dev/null
sudo chmod 600 "${RESTRICTED_HOME}/.ssh/authorized_keys"

success "SSH key pair generated"
info "Private key: ${RESTRICTED_HOME}/.ssh/id_ed25519"

# Configure SSH Match block
step "Configuring SSH for restricted user"
SSHD_MATCH_BLOCK="# BEGIN RESTRICTED USER: ${RESTRICTED_USER}
Match User ${RESTRICTED_USER}
    AllowTcpForwarding yes
    GatewayPorts ${ALLOW_GATEWAY_PORTS}
    X11Forwarding no
    PermitTTY no
# END RESTRICTED USER: ${RESTRICTED_USER}"

# Remove existing block if present
if sudo grep -q "Match User ${RESTRICTED_USER}" "${SSHD_CONFIG_FILE}"; then
  info "Updating existing Match block..."
  sudo sed -i "/# BEGIN RESTRICTED USER: ${RESTRICTED_USER}/,/# END RESTRICTED USER: ${RESTRICTED_USER}/d" "${SSHD_CONFIG_FILE}"
fi

# Append new block
echo "${SSHD_MATCH_BLOCK}" | sudo tee -a "${SSHD_CONFIG_FILE}" > /dev/null

# Set home permissions
sudo chown "${RESTRICTED_USER}:${RESTRICTED_USER}" "${RESTRICTED_HOME}"
sudo chmod 700 "${RESTRICTED_HOME}"

# Validate and restart SSH
step "Validating SSH configuration"
if sudo sshd -t; then
  success "SSH configuration is valid"
else
  error "SSH configuration is invalid. Check ${SSHD_CONFIG_FILE}"
fi

step "Restarting SSH service"
sudo systemctl restart ssh

# Summary
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
success "Restricted user setup complete!"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo "Username:  ${RESTRICTED_USER}"
echo "Home:      ${RESTRICTED_HOME}"
echo "Key:       ${RESTRICTED_HOME}/.ssh/id_ed25519"
echo ""
echo "Tunnel usage:"
echo "  Local:  ssh -N -o IdentitiesOnly=yes -L 1235:localhost:1234 -p ${SSHD_PORT} ${RESTRICTED_USER}@<host> -i <key>"
echo "  Remote: ssh -N -o IdentitiesOnly=yes -R 0.0.0.0:port:localhost:localport -p ${SSHD_PORT} ${RESTRICTED_USER}@<host> -i <key>"