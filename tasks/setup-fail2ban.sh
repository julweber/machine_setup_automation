#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-fail2ban.sh — Install and configure fail2ban with custom SSH port
# =============================================================================
#
# Description:
#   Installs fail2ban, applies the Python 3.12 compatibility fix (pyasynchat),
#   and configures it to monitor the custom SSH port with sensible defaults.
#
# Environment Variables (optional):
#   FAIL2BAN_SSHD_PORT  - Custom SSH port to monitor (default: ${SSHD_PORT} or 2224)
#   FAIL2BAN_MAXRETRY   - Max failed attempts before ban (default: 5)
#   FAIL2BAN_BANTIME    - Ban duration in seconds (default: 3600)
#   FAIL2BAN_FINDTIME   - Time window for detecting attempts (default: 600)
#
# Usage:
#   ./setup-fail2ban.sh
#   FAIL2BAN_SSHD_PORT=2222 ./setup-fail2ban.sh
#   ./setup-fail2ban.sh --help
#
# Python 3.12 Compatibility:
#   Python 3.12 removed the asynchat/asyncore modules from the standard library.
#   This script installs pyasynchat to restore compatibility.
#
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

# ---------------------------------------------------------------------------
# USAGE / HELP
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [OPTIONS]

Installs fail2ban, applies the Python 3.12 compatibility fix (pyasynchat),
and configures it to monitor the custom SSH port with sensible defaults.
Uses sudo internally.

${BOLD}Options:${RESET}
  -h, --help    Show this help and exit

${BOLD}Environment variables${RESET} (all optional):
  FAIL2BAN_SSHD_PORT    Custom SSH port to monitor (default: ${SSHD_PORT:-2224})
  FAIL2BAN_MAXRETRY     Max failed attempts before ban (default: 5)
  FAIL2BAN_BANTIME      Ban duration in seconds (default: 3600)
  FAIL2BAN_FINDTIME     Time window for detecting attempts (default: 600)
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1 (see --help)"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
: "${FAIL2BAN_SSHD_PORT:=${SSHD_PORT:-2224}}"
: "${FAIL2BAN_MAXRETRY:=5}"
: "${FAIL2BAN_BANTIME:=3600}"
: "${FAIL2BAN_FINDTIME:=600}"

JAIL_LOCAL="/etc/fail2ban/jail.local"
TEMPLATE_DIR="${SCRIPT_DIR}/../templates/fail2ban"
# shellcheck disable=SC2034
GENERATED_DATE="$(date -Iseconds)"

# ---------------------------------------------------------------------------
# Python 3.12 Compatibility Fix
# ---------------------------------------------------------------------------
step "Checking Python 3.12 compatibility"

PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+')
PYTHON_MAJOR=$(echo "${PYTHON_VERSION}" | cut -d. -f1)
PYTHON_MINOR=$(echo "${PYTHON_VERSION}" | cut -d. -f2)

if [[ "${PYTHON_MAJOR}" -ge 3 ]] && [[ "${PYTHON_MINOR}" -ge 12 ]]; then
  info "Python ${PYTHON_VERSION} detected — asynchat was removed in 3.12"

  if ! python3 -c "import asynchat" 2>/dev/null; then
    info "Installing pyasynchat for Python 3.12+ compatibility"
    if command -v pip3 &>/dev/null; then
      sudo pip3 install pyasynchat --break-system-packages 2>/dev/null || \
      sudo pip3 install pyasynchat
    else
      sudo apt update
      sudo apt install -y python3-pip
      sudo pip3 install pyasynchat --break-system-packages 2>/dev/null || \
      sudo pip3 install pyasynchat
    fi

    # Verify the module is importable
    if python3 -c "import asynchat" 2>/dev/null; then
      success "pyasynchat installed successfully"
    else
      error "Failed to install pyasynchat. fail2ban will not start."
    fi
  else
    info "asynchat module already available"
  fi
else
  info "Python ${PYTHON_VERSION} — asynchat is available in standard library"
fi

# ---------------------------------------------------------------------------
# Install fail2ban
# ---------------------------------------------------------------------------
step "Installing fail2ban"

# Check if fail2ban is already installed
if command -v fail2ban-server &>/dev/null; then
  info "fail2ban is already installed: $(fail2ban-server --version 2>/dev/null || echo 'unknown')"
else
  # Add fail2ban repository for latest version
  info "Adding fail2ban repository"
  sudo apt install -y gnupg
  sudo wget -O /etc/apt/keyrings/fail2ban.asc https://repo.fail2ban.org/etc/gpg/fail2ban.gpg 2>/dev/null || true

  # Get the codename from /etc/os-release (replaces deprecated lsb_release)
  # shellcheck disable=SC1091  # /etc/os-release is a runtime system file
  DISTRO=$(. /etc/os-release && echo "${VERSION_CODENAME}")
  if [[ -z "${DISTRO}" ]]; then
    DISTRO="noble"
    warn "Could not determine codename, using 'noble' as default"
  fi
  echo "deb [signed-by=/etc/apt/keyrings/fail2ban.asc] https://repo.fail2ban.org/debian/ ${DISTRO} main" | \
    sudo tee /etc/apt/sources.list.d/fail2ban.list > /dev/null

  sudo apt update
  sudo apt install -y fail2ban
  success "fail2ban installed"
fi

# ---------------------------------------------------------------------------
# Start and enable fail2ban service
# ---------------------------------------------------------------------------
step "Starting fail2ban service"

if ! sudo systemctl is-active fail2ban &>/dev/null; then
  sudo systemctl enable fail2ban
  sudo systemctl start fail2ban
  success "fail2ban service started"
else
  info "fail2ban service is already running"
fi

# Verify service is running
if sudo systemctl is-active fail2ban &>/dev/null; then
  success "fail2ban service is active"
else
  error "fail2ban failed to start. Check: sudo systemctl status fail2ban"
fi

# ---------------------------------------------------------------------------
# Configure fail2ban
# ---------------------------------------------------------------------------
step "Configuring fail2ban"

# Create jail.local configuration
if [[ -f "${JAIL_LOCAL}" ]]; then
  info "Existing ${JAIL_LOCAL} found — updating sshd jail settings"
else
  info "Creating new ${JAIL_LOCAL}"
fi

# Check envsubst for template rendering
if ! command -v envsubst &>/dev/null; then
  error "envsubst is not installed. Required for template rendering. Install with: sudo apt-get install gettext-base"
fi

# Render template and write configuration
info "Rendering configuration from template"
sudo cat "${TEMPLATE_DIR}/jail.local" \
  | sudo envsubst '${FAIL2BAN_SSHD_PORT} ${FAIL2BAN_MAXRETRY} ${FAIL2BAN_BANTIME} ${FAIL2BAN_FINDTIME} ${GENERATED_DATE}' \
  | sudo tee "${JAIL_LOCAL}" > /dev/null

# Configuration written to /etc/fail2ban/jail.local above

# Reload fail2ban to apply configuration
sudo fail2ban-client reload 2>/dev/null || sudo systemctl restart fail2ban

success "fail2ban configured"

# ---------------------------------------------------------------------------
# Verify Configuration
# ---------------------------------------------------------------------------
step "Verifying configuration"

# Check jail status
if sudo fail2ban-client status sshd &>/dev/null; then
  success "SSHD jail is active"
  info "Jail status:"
  sudo fail2ban-client status sshd
else
  warn "Could not verify jail status"
fi

# Display configuration summary
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  fail2ban Setup Complete${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
info "Configuration file: ${JAIL_LOCAL}"
echo ""
echo -e "${BOLD}Quick Commands:${RESET}"
echo "  Status:          sudo fail2ban-client status"
echo "  Jail status:     sudo fail2ban-client status sshd"
echo "  Banned IPs:      sudo fail2ban-client get sshd banip"
echo "  Unban IP:        sudo fail2ban-client set sshd unbanip <IP>"
echo "  Restart:         sudo systemctl restart fail2ban"
echo "  Logs:            sudo tail -f /var/log/fail2ban.log"
echo ""
echo -e "${BOLD}Connect to your SSH server:${RESET}"
echo "  ssh -p ${FAIL2BAN_SSHD_PORT} $(whoami)@$(hostname -I | awk '{print $1}')"
echo ""
