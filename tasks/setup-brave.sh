#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-brave.sh — Install Brave Browser
# =============================================================================
#
# Description:
#   Installs the Brave web browser on Debian/Ubuntu-based systems by adding
#   the official Brave repository and installing the brave-browser package.
#
# Usage:
#   ./setup-brave.sh
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
BRAVE_GPG_KEY_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
BRAVE_SOURCES_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser.sources"
BRAVE_GPG_PATH="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
BRAVE_SOURCES_PATH="/etc/apt/sources.list.d/brave-browser-release.sources"

# =============================================================================
# Main
# =============================================================================

step "Setting up Brave Browser"

# Check if Brave is already installed
if dpkg -l brave-browser &>/dev/null; then
  success "Brave Browser is already installed"
  exit 0
fi

info "Installing Brave Browser..."

# Check prerequisites
if ! command -v curl &>/dev/null; then
  error "curl is not installed. Please install curl first."
fi

# Download GPG key
step "Downloading Brave GPG key"
if [[ -f "${BRAVE_GPG_PATH}" ]]; then
  info "GPG key already exists at ${BRAVE_GPG_PATH}"
else
  sudo curl -fsSLo "${BRAVE_GPG_PATH}" "${BRAVE_GPG_KEY_URL}"
fi

# Download sources file
step "Configuring Brave repository"
if [[ -f "${BRAVE_SOURCES_PATH}" ]]; then
  info "Sources file already exists at ${BRAVE_SOURCES_PATH}"
else
  sudo curl -fsSLo "${BRAVE_SOURCES_PATH}" "${BRAVE_SOURCES_URL}"
fi

# Install Brave
step "Installing Brave Browser"
sudo apt update
sudo apt install -y brave-browser

success "Brave Browser installed successfully"
info "Run 'brave-browser' to start the browser"