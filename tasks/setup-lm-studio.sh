#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-lm-studio.sh — Install LM Studio
# =============================================================================
#
# Description:
#   Installs LM Studio on Linux systems with AppImage and optionally installs
#   the llmster CLI tool (lms).
#
# Environment Variables (optional):
#   LM_STUDIO_VERSION       - Specific version (default: auto-detect latest)
#   INSTALL_LLMSTER_ENABLED - Install llmster CLI (default: true)
#
# Usage:
#   ./setup-lm-studio.sh
#   LM_STUDIO_VERSION=0.4.5-2 ./setup-lm-studio.sh
#   INSTALL_LLMSTER_ENABLED=false ./setup-lm-studio.sh
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
: "${INSTALL_LLMSTER_ENABLED:=true}"
DEFAULT_LM_STUDIO_VERSION="0.4.6-1"
: "${LM_STUDIO_VERSION:=${DEFAULT_LM_STUDIO_VERSION}}"

DESKTOP_LINK_TARGET_PATH="${DESKTOP_LINK_TARGET_PATH:-$HOME/Desktop/LM-Studio.desktop}"
START_SCRIPT_TARGET_PATH="${START_SCRIPT_TARGET_PATH:-$HOME/lmstudio}"
APP_IMAGE_TARGET_PATH="${APP_IMAGE_TARGET_PATH:-$HOME/lmstudio_bin}"
APP_IMAGE_BACKUP_PATH="${APP_IMAGE_BACKUP_PATH:-$HOME/lmstudio_bin_backup}"

# Architecture detection
LATEST_URL_AMD64="https://lmstudio.ai/download/latest/linux/x64"
LATEST_URL_ARM64="https://lmstudio.ai/download/latest/linux/arm64"

ARCH=$(uname -m)
case "${ARCH}" in
  x86_64)
    ARCH_TYPE="x64"
    LATEST_URL="${LATEST_URL_AMD64}"
    ;;
  aarch64|arm64)
    ARCH_TYPE="arm64"
    LATEST_URL="${LATEST_URL_ARM64}"
    ;;
  *)
    error "Unsupported architecture: ${ARCH}. Only amd64 and arm64 are supported."
    ;;
esac

# =============================================================================
# Main
# =============================================================================

step "Setting up LM Studio"

info "Detected architecture: ${ARCH} (${ARCH_TYPE})"

# Auto-detect version if using default
if [[ "${LM_STUDIO_VERSION}" == "${DEFAULT_LM_STUDIO_VERSION}" ]]; then
  step "Detecting latest version"
  FINAL_URL=$(curl -sI -L "${LATEST_URL}" -o /dev/null -w '%{url_effective}')
  LM_STUDIO_VERSION=$(echo "${FINAL_URL}" | grep -oP -m1 '[\d]+\.[\d]+\.[\d]+-[\d]+' | head -1)
  info "Latest version: ${LM_STUDIO_VERSION}"
fi

SOURCE_URL="https://installers.lmstudio.ai/linux/${ARCH_TYPE}/${LM_STUDIO_VERSION}/LM-Studio-${LM_STUDIO_VERSION}-${ARCH_TYPE}.AppImage"
info "Download URL: ${SOURCE_URL}"

# Create start script
if [[ -f "${START_SCRIPT_TARGET_PATH}" ]]; then
  info "Start script exists at: ${START_SCRIPT_TARGET_PATH}"
else
  step "Creating start script"
  cat > "${START_SCRIPT_TARGET_PATH}" << 'EOF'
#!/usr/bin/env bash
cd "$HOME"
./lmstudio_bin --no-sandbox
EOF
fi

chmod +x "${START_SCRIPT_TARGET_PATH}"

# Create desktop link
if [[ -f "${DESKTOP_LINK_TARGET_PATH}" ]]; then
  info "Desktop link exists at: ${DESKTOP_LINK_TARGET_PATH}"
else
  step "Creating desktop shortcut"
  cat > "${DESKTOP_LINK_TARGET_PATH}" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=LM Studio
Comment=LM Studio
Icon=utilities-terminal
Exec=${START_SCRIPT_TARGET_PATH}
EOF
fi

chmod +x "${DESKTOP_LINK_TARGET_PATH}"

# Handle existing binary
if [[ -f "${APP_IMAGE_TARGET_PATH}" ]]; then
  info "Existing binary found: ${APP_IMAGE_TARGET_PATH}"
  info "Backing up to: ${APP_IMAGE_BACKUP_PATH}"
  mv "${APP_IMAGE_TARGET_PATH}" "${APP_IMAGE_BACKUP_PATH}"
fi

# Download AppImage
step "Downloading LM Studio v${LM_STUDIO_VERSION}"
wget --output-document "${APP_IMAGE_TARGET_PATH}" "${SOURCE_URL}"
chmod +x "${APP_IMAGE_TARGET_PATH}"
success "Installed version: ${LM_STUDIO_VERSION}"

# Install llmster CLI
if [[ "${INSTALL_LLMSTER_ENABLED}" == "true" ]]; then
  step "Installing llmster CLI"
  # Don't fail script on errors for this command
  set +e
  curl -fsSL https://lmstudio.ai/install.sh | bash
  if command -v lms &>/dev/null; then
    info "lms version: $(lms --version 2>/dev/null || echo 'unknown')"
  fi
  set -e
else
  info "llmster install disabled"
fi

success "LM Studio installed successfully"
info "Run '${START_SCRIPT_TARGET_PATH}' to start the application"