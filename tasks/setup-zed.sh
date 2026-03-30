#!/usr/bin/env bash
#
# Setup Zed Editor
#
# Description:
#   Installs the Zed editor on Linux using the official installation script.
#   Supports both stable and preview channels.
#
# Key Actions:
#   1. Downloads and executes the official Zed installation script
#   2. Installation location: ~/.local/zed.app/
#   3. Binary symlinked to: ~/.local/bin/zed (or /usr/local/bin if writable)
#
# System Requirements:
#   - Vulkan compatible GPU available
#   - glibc >= 2.31 for x86_64 (Ubuntu 20 and newer)
#   - glibc >= 2.35 for aarch64 (Ubuntu 22 and newer)
#
# Environment Variables (optional):
#   ZED_CHANNEL=preview - Install preview build instead of stable
#
# Usage:
#   ./setup-zed.sh           # Install stable version
#   ZED_CHANNEL=preview ./setup-zed.sh  # Install preview version
#
# Important URLs:
#   - Installation script: https://zed.dev/install.sh
#   - Download page: https://zed.dev/download
#
# Exit Behavior:
#   - Script will exit on any error (set -e)
#   - Script will exit on undefined variables (set -u)
#
set -eu

echo "Installing Zed Editor..."

# Run the official Zed installation script
curl -f https://zed.dev/install.sh | sh

echo ""
echo "Zed installed successfully!"
echo "To run Zed, use: zed"
echo "To uninstall: zed --uninstall"
