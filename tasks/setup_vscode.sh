#!/usr/bin/env bash
################################################################################
# VSCode Installation Script
#
# Description:
#   Installs Visual Studio Code (VSCode) on Debian/Ubuntu-based systems by
#   adding the official Microsoft repository and installing the 'code' package.
#
# Key Actions:
#   1. Downloads and installs Microsoft's GPG signing key
#   2. Adds the key to the system's trusted keyrings directory
#   3. Configures the VSCode APT repository (stable channel)
#   4. Updates the APT package cache
#   5. Installs the VSCode package ('code')
#   6. Cleans up temporary GPG key file
#
# Dependencies:
#   - wget: For downloading the Microsoft GPG key
#   - gpg: For handling GPG key operations
#   - apt: Package manager (Debian/Ubuntu)
#   - sudo: Required for system-level operations
#
# Supported Architectures:
#   - amd64 (x86_64)
#   - arm64 (ARM 64-bit)
#   - armhf (ARM hard-float)
#
# Notes:
#   - Script exits on any error (set -eu)
#   - Requires sudo privileges for package installation
#   - Uses Microsoft's official stable repository
################################################################################
set -eu

# VSCode
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" |sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
rm -f packages.microsoft.gpg

sudo apt update
sudo apt install -y code