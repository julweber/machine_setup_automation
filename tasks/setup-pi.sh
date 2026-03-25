#!/usr/bin/env bash

################################################################################
# Script: setup-pi.sh
# Description: Installs and configures the Pi coding agent environment
#
# This script sets up the Pi coding agent (by Mario Zechner) which is an AI
# coding assistant CLI tool. It ensures the latest Node.js version is installed
# and then installs the Pi coding agent globally via npm.
#
# Key Actions:
#   1. Installs the latest Node.js version using nvm (Node Version Manager)
#   2. Installs the Pi coding agent package globally from npm
#
# Dependencies:
#   - nvm (Node Version Manager) must be installed and available in PATH
#   - npm (comes with Node.js installation)
#   - Internet connection for downloading packages
#
# Important Variables:
#   - Uses 'set -euo pipefail' for strict error handling:
#     * -e: Exit immediately if a command exits with non-zero status
#     * -u: Treat unset variables as errors
#     * -o pipefail: Return exit status of last command in pipe that failed
#
# Package Installed:
#   - @mariozechner/pi-coding-agent (global npm package)
#
################################################################################

set -euo pipefail

# Load NVM if not already loaded
if ! command -v nvm &> /dev/null; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

echo "Installing latest node version..."
nvm install node

echo "Installing pi coding agent..."
npm install -g @mariozechner/pi-coding-agent
pi install npm:pi-subagents
pi install npm:pi-mcp-adapter
pi install npm:pi-markdown-preview
pi install npm:pi-web-access
pi install npm:pi-extmgr
pi update