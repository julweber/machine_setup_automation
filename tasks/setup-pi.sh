#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-pi.sh — Install Pi coding agent
# =============================================================================
#
# Description:
#   Installs and configures the Pi coding agent environment.
#   Ensures latest Node.js version is installed and then installs Pi globally.
#
# Environment Variables (optional):
#   NVM_DIR - NVM directory path (default: $HOME/.nvm)
#
# Usage:
#   ./setup-pi.sh
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
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# Pi extensions to install
declare -a PI_EXTENSIONS=(
  "npm:pi-subagents"
  "npm:pi-mcp-adapter"
  "npm:pi-markdown-preview"
  "npm:pi-web-access"
  "npm:pi-extmgr"
  "https://github.com/gsanhueza/pi-token-speed"
)

# =============================================================================
# Main
# =============================================================================

step "Setting up Pi coding agent"

# Load NVM if not already loaded
if ! command -v nvm &>/dev/null; then
  step "Loading NVM"
  export NVM_DIR
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

# Check if nvm is available now
if ! command -v nvm &>/dev/null; then
  error "NVM is not installed. Please install NVM first."
fi

# Install latest Node.js
step "Installing latest Node.js version"
nvm install node

# Check if Pi is already installed
if command -v pi &>/dev/null; then
  info "Pi coding agent is already installed: $(pi --version 2>/dev/null || echo 'version unknown')"
  info "Updating Pi..."
else
  step "Installing Pi coding agent"
fi

npm install -g @earendil-works/pi-coding-agent

# Install Pi extensions
step "Installing Pi extensions"
for extension in "${PI_EXTENSIONS[@]}"; do
  info "Installing: ${extension}"
  pi install "${extension}"
done

# Update Pi
step "Updating Pi extensions"
pi update

# Install Codegraph
step "Installing Codegraph"
npx @colbymchenry/codegraph install -y

# Install Playwright
step "Installing Playwright browsers and dependencies"
npx playwright install-deps
npx playwright install
npx playwright install chrome

success "Pi coding agent installed successfully"
info "Run 'pi --help' to see available commands"
