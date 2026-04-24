#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-whispering.sh — Install Whispering
# =============================================================================
#
# Description:
#   Automates the installation and setup of Whispering on Linux systems.
#   Downloads the AppImage binary, creates startup scripts, and configures
#   desktop integration.
#
# Options:
#   --force     Reinstall even if Whispering is already installed
#   --help      Display this help message
#
# Usage:
#   ./setup-whispering.sh              # Install Whispering (latest version)
#   ./setup-whispering.sh --force      # Reinstall (force)
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
ARCH="$(detect_arch || echo amd64)"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../templates/whispering"

DESKTOP_LINK_TARGET_PATH="${DESKTOP_LINK_TARGET_PATH:-$HOME/Desktop/Whispering.desktop}"
START_SCRIPT_TARGET_PATH="${START_SCRIPT_TARGET_PATH:-$HOME/whispering}"
APP_IMAGE_TARGET_PATH="${APP_IMAGE_TARGET_PATH:-$HOME/whispering_bin}"
APP_IMAGE_BACKUP_PATH="${APP_IMAGE_BACKUP_PATH:-$HOME/whispering_bin_backup}"
VERSION_MARKER_PATH="${APP_IMAGE_TARGET_PATH}.version"

# =============================================================================
# Help
# =============================================================================

show_help() {
  cat << 'EOF'
Usage: setup-whispering.sh [OPTIONS]

Install Whispering desktop application on Linux.

Options:
  --force    Reinstall even if Whispering is already installed
  --help     Display this help message

Examples:
  ./setup-whispering.sh              # Install Whispering (latest version)
  ./setup-whispering.sh --force      # Reinstall (force)

For more information, visit: https://github.com/EpicenterHQ/epicenter
EOF
}

# =============================================================================
# Argument parsing
# =============================================================================

FORCE_INSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE_INSTALL=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      error "Unknown option: $1. Use --help for usage information."
      ;;
  esac
done

# =============================================================================
# Cleanup trap
# =============================================================================

cleanup() {
  # Remove partial/corrupt downloads on failure
  if [[ -f "${APP_IMAGE_TARGET_PATH}" ]] && ! file "${APP_IMAGE_TARGET_PATH}" 2>/dev/null | grep -q "ELF"; then
    rm -f "${APP_IMAGE_TARGET_PATH}"
    warn "Removed partial/corrupt download"
  fi
}
trap cleanup EXIT

# =============================================================================
# Main
# =============================================================================

# Fetch latest release version from GitHub
step "Fetching latest Whispering version from GitHub"
WHISPERING_VERSION=$(curl -fsSL "https://api.github.com/repos/EpicenterHQ/epicenter/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"v\K[^"]+' || echo "")
if [[ -z "${WHISPERING_VERSION}" ]]; then
  error "Could not determine latest Whispering version from GitHub"
  exit 1
fi
SOURCE_URL="https://github.com/EpicenterHQ/epicenter/releases/download/v${WHISPERING_VERSION}/Whispering_${WHISPERING_VERSION}_${ARCH}.AppImage"
step "Setting up Whispering (version: ${WHISPERING_VERSION})"

# Check prerequisites
if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
  error "Neither wget nor curl is installed. Please install one first."
fi

# Create start script
if [[ -f "${START_SCRIPT_TARGET_PATH}" ]]; then
  info "Start script exists at: ${START_SCRIPT_TARGET_PATH}. Skipping creation."
else
  step "Creating start script at: ${START_SCRIPT_TARGET_PATH}"
  APP_IMAGE_TARGET_PATH="${APP_IMAGE_TARGET_PATH}" envsubst < "${TEMPLATE_DIR}/start-script.sh.template" > "${START_SCRIPT_TARGET_PATH}"
fi

chmod +x "${START_SCRIPT_TARGET_PATH}"

# Create desktop link
if [[ -f "${DESKTOP_LINK_TARGET_PATH}" ]]; then
  info "Desktop link exists at: ${DESKTOP_LINK_TARGET_PATH}. Skipping creation."
else
  step "Creating desktop link at: ${DESKTOP_LINK_TARGET_PATH}"
  START_SCRIPT_TARGET_PATH="${START_SCRIPT_TARGET_PATH}" envsubst < "${TEMPLATE_DIR}/whispering.desktop.template" > "${DESKTOP_LINK_TARGET_PATH}"
fi

chmod +x "${DESKTOP_LINK_TARGET_PATH}"

# Check if correct version is already installed
if [[ -f "${APP_IMAGE_TARGET_PATH}" ]]; then
  if [[ "${FORCE_INSTALL}" == "true" ]]; then
    warn "Whispering binary exists, --force specified, proceeding with reinstallation..."
  else
    # Check version marker file
    INSTALLED_VERSION=""
    if [[ -f "${VERSION_MARKER_PATH}" ]]; then
      INSTALLED_VERSION=$(cat "${VERSION_MARKER_PATH}")
    fi
    if [[ "${INSTALLED_VERSION}" == "${WHISPERING_VERSION}" ]]; then
      success "Whispering ${WHISPERING_VERSION} is already installed (latest release)"
      info "Run '${START_SCRIPT_TARGET_PATH}' to start the application"
      exit 0
    fi
    if [[ -n "${INSTALLED_VERSION}" ]]; then
      info "Different version installed (${INSTALLED_VERSION}), upgrading to ${WHISPERING_VERSION}"
    else
      info "Unknown version installed, upgrading to ${WHISPERING_VERSION}"
    fi
  fi
  info "Backing up existing binary to ${APP_IMAGE_BACKUP_PATH}"
  cp -p "${APP_IMAGE_TARGET_PATH}" "${APP_IMAGE_BACKUP_PATH}"
fi

# Download AppImage
step "Downloading Whispering AppImage"
info "From: ${SOURCE_URL}"
info "To: ${APP_IMAGE_TARGET_PATH}"

# Download with retry logic
for attempt in 1 2 3; do
  if wget --output-document "${APP_IMAGE_TARGET_PATH}" "${SOURCE_URL}" 2>&1; then
    break
  fi
  warn "Download attempt ${attempt} failed, retrying..."
  sleep 2
done

# Verify checksum if available
if command -v sha256sum &>/dev/null; then
  step "Verifying download integrity"
  CHECKSUM_URL="${SOURCE_URL%.AppImage}.sha256"
  if curl -fsSL "${CHECKSUM_URL}" -o "${APP_IMAGE_TARGET_PATH}.sha256" 2>/dev/null; then
    if sha256sum -c "${APP_IMAGE_TARGET_PATH}.sha256" >/dev/null 2>&1; then
      success "Checksum verification passed"
    else
      error "Checksum verification failed!"
      exit 1
    fi
    rm -f "${APP_IMAGE_TARGET_PATH}.sha256"
  else
    warn "Could not download checksum file, skipping verification"
  fi
fi

chmod +x "${APP_IMAGE_TARGET_PATH}"

# Write version marker file
step "Writing version marker"
echo "${WHISPERING_VERSION}" > "${VERSION_MARKER_PATH}"

success "Whispering version ${WHISPERING_VERSION} installed successfully"
info "Run '${START_SCRIPT_TARGET_PATH}' to start the application"