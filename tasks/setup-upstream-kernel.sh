#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-upstream-kernel.sh — Install Zabbly mainline kernel repo
# =============================================================================
#
# Description:
#   Prepares the Zabbly mainline kernel apt repository on Ubuntu.
#   https://pkgs.zabbly.com/kernel/stable
#
# Usage:
#   ./setup-upstream-kernel.sh
#   ./setup-upstream-kernel.sh --help
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

# =============================================================================
# USAGE / HELP
# =============================================================================

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [OPTIONS]

Prepares the Zabbly mainline kernel apt repository on Ubuntu
(https://pkgs.zabbly.com/kernel/stable): installs the GPG keyring,
adds the sources file, and updates the package lists. Uses sudo internally.

${BOLD}Options:${RESET}
  --interactive   Prompt for confirmation on risky conditions
  -h, --help      Show this help and exit

${BOLD}Notes:${RESET}
  - Ubuntu only (tested with noble/jammy).
  - Secure Boot check: Zabbly kernels are unsigned and will not boot with
    Secure Boot enabled.
  - Mainline kernels may break NVIDIA drivers.
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

# Configuration
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="${KEYRING_DIR}/zabbly.asc"
SOURCES_FILE="/etc/apt/sources.list.d/zabbly-kernel-stable.sources"

# =============================================================================
# Helper functions
# =============================================================================

check_supported_distro() {
  # shellcheck disable=SC1091
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS. /etc/os-release not found."
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "$ID" != "ubuntu" ]]; then
    error "This script is intended for Ubuntu only (detected: $ID)."
  fi
  case "$VERSION_CODENAME" in
    noble|jammy) ;;
    *) warn "Unsupported Ubuntu release '$VERSION_CODENAME'. Proceeding anyway..." ;;
  esac
  info "Detected Ubuntu ${VERSION_ID} (${VERSION_CODENAME})"
}

check_secure_boot() {
  if command -v mokutil &>/dev/null; then
    if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
      warn "Secure Boot is ENABLED."
      warn "Zabbly kernels are unsigned and will NOT boot with Secure Boot on."
      echo ""
      if [[ "$INTERACTIVE" == "true" ]]; then
        read -rp "Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
      else
        error "Secure Boot is enabled and Zabbly kernels are unsigned. Disable Secure Boot in UEFI/BIOS, or re-run with --interactive to confirm manually."
      fi
    else
      success "Secure Boot is disabled."
    fi
  else
    warn "mokutil not found; cannot check Secure Boot status."
  fi
}

check_nvidia() {
  if lsmod 2>/dev/null | grep -q "^nvidia"; then
    warn "NVIDIA kernel module detected."
    warn "Mainline kernels may break NVIDIA drivers."
    echo ""
    if [[ "$INTERACTIVE" == "true" ]]; then
      read -rp "Continue anyway? [y/N] " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    else
      error "NVIDIA kernel module is loaded and mainline kernels may break NVIDIA drivers. Verify driver compatibility with the mainline kernel, or re-run with --interactive to confirm manually."
    fi
  fi
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Zabbly Mainline Kernel Repository Setup    ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""

check_supported_distro
check_secure_boot
check_nvidia

# Install dependencies
step "Installing dependencies"
sudo apt-get install -y --quiet curl apt-transport-https ca-certificates
success "Dependencies installed."

# Setup keyring
step "Setting up Zabbly signing key"
if [[ -f "${KEYRING_FILE}" ]]; then
  info "Keyring already exists at ${KEYRING_FILE}"
else
  sudo mkdir -p "${KEYRING_DIR}"
  info "Downloading Zabbly signing key..."
  curl -fsSL https://pkgs.zabbly.com/key.asc \
    | sudo tee "${KEYRING_FILE}" > /dev/null \
    || error "Failed to download Zabbly signing key"
  sudo chmod 644 "${KEYRING_FILE}"
fi
success "Signing key ready."

# Setup repository
step "Configuring repository"
# shellcheck disable=SC1091
source /etc/os-release

if [[ -f "${SOURCES_FILE}" ]]; then
  info "Repository file exists"
  CURRENT_SUITE=$(grep "^Suites:" "${SOURCES_FILE}" | awk '{print $2}')
  if [[ "${CURRENT_SUITE}" == "${VERSION_CODENAME}" ]]; then
    success "Repository already configured for '${VERSION_CODENAME}'"
  else
    warn "Updating repository for '${VERSION_CODENAME}'"
  fi
fi

cat <<EOF | sudo tee "${SOURCES_FILE}" > /dev/null
Enabled: yes
Types: deb deb-src
URIs: https://pkgs.zabbly.com/kernel/stable
Suites: ${VERSION_CODENAME}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: ${KEYRING_FILE}
EOF

success "Repository configured for '${VERSION_CODENAME}'"

# Update package index
step "Updating package index"
sudo apt-get update -q || error "apt-get update failed"
success "Package index updated."

# Summary
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
success "Repository setup complete!"
info "Currently running: $(uname -r)"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
echo ""
info "To list available kernels:"
echo -e "  ${CYAN}apt-cache search linux-zabbly${RESET}"
echo ""
info "To install:"
echo -e "  ${CYAN}sudo apt-get install linux-zabbly-6.8.0-mainline${RESET}"
echo ""
warn "Reboot after installation to use the new kernel."