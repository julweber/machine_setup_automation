#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-basics.sh — Install essential development tools
# =============================================================================
#
# Description:
#   Installs essential system packages and tools for development environment.
#
# Environment Variables (optional):
#   NVM_VERSION - NVM version to install (default: 0.40.4)
#   NVM_DIR     - NVM installation directory (default: $HOME/.nvm)
#
# Usage:
#   ./setup-basics.sh
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
: "${NVM_VERSION:=0.40.4}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# Packages to install
declare -a APT_PACKAGES=(
  curl
  tldr
  bat
  git
  python3-full
  python3-pip
  jq
  yq
  net-tools
  wget
  gpg
  netcat-openbsd
  terminator
  libfuse2
  gnome-control-center
  gnome-online-accounts
  nvtop
  radeontop
  btop
  htop
  tmux
  nodejs
  npm
  spirv-headers
)

# =============================================================================
# Main
# =============================================================================

step "Setting up development basics"

# Update package lists
step "Updating package lists"
sudo apt update

# Install apt packages
step "Installing packages"
for pkg in "${APT_PACKAGES[@]}"; do
  if dpkg -l "$pkg" &>/dev/null; then
    info "$pkg already installed"
  else
    info "Installing $pkg"
    sudo apt install -y "$pkg"
  fi
done

# Install uv (Python package manager)
step "Installing uv"
if command -v uv &>/dev/null; then
  success "uv already installed"
else
  info "Installing uv..."
  pip install uv --break-system-packages
fi

# Install NVM
step "Installing NVM v${NVM_VERSION}"
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  success "NVM already installed at ${NVM_DIR}"
else
  info "Installing NVM..."
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
fi

# Add NVM configuration to ~/.profile
step "Configuring NVM in ~/.profile"
PROFILE="$HOME/.profile"
NVM_CONFIG="
# NVM configuration
export NVM_DIR=\"${NVM_DIR}\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"  # This loads nvm
[ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\"  # This loads nvm bash_completion
"

if [[ ! -s "${PROFILE}" ]] || ! grep -q "export NVM_DIR=" "${PROFILE}"; then
  echo "${NVM_CONFIG}" >> "${PROFILE}"
  info "NVM configuration added to ${PROFILE}"
else
  info "NVM configuration already present in ${PROFILE}"
fi

# Load NVM into current session
# shellcheck disable=SC1091
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  export NVM_DIR
  \. "${NVM_DIR}/nvm.sh"
  info "NVM loaded into current session"
fi

# Install huggingface-cli
step "Installing huggingface-cli"
if command -v hf &>/dev/null; then
  success "huggingface-cli already installed"
else
  info "Installing huggingface-cli..."
  curl -LsSf https://hf.co/cli/install.sh | bash
fi

# Install herdr
step "Installing herdr"
if command -v herdr &>/dev/null; then
  success "herdr already installed. Updating version to latest..."
  herdr update
else
  info "Installing herdr..."
  curl -LsSf https://herdr.dev/install.sh | bash
fi

# Install hunk
step "Installing hunk"
if command -v hunk &>/dev/null; then
  success "hunk already installed. Updating to latest..."
  npm update -g hunkdiff
else
  info "Installing hunk..."
  npm i -g hunkdiff
fi

success "Development basics installed successfully"
