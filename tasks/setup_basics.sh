#!/usr/bin/env bash
################################################################################
# Script: setup_basics.sh
# Description: Installs essential system packages and tools for development
#              environment setup on Debian/Ubuntu-based systems.
#
# Key Actions:
#   1. Updates apt package lists
#   2. Installs core utilities (curl, wget, git, jq, yq, net-tools, gpg)
#   3. Installs terminal tools (tldr, bat, terminator, tmux)
#   4. Installs Python 3 (full install) and pip
#   5. Installs system monitoring tools (nvtop, radeontop, btop, htop)
#   6. Installs Node.js and npm via apt
#   7. Installs Python package manager 'uv' via pip
#   8. Installs and configures Node Version Manager (NVM)
#   9. Loads NVM into current shell session
#
# Important Variables:
#   NVM_VERSION - Version of NVM to install (default: 0.40.4)
#   NVM_DIR     - NVM installation directory (default: $HOME/.nvm)
#
# Dependencies:
#   - Debian/Ubuntu-based Linux distribution
#   - sudo privileges for apt package installation
#   - Internet connection for downloading packages and NVM
#   - pip (installed during script execution)
#
# Notes:
#   - Script exits on any error (set -e)
#   - Script exits on undefined variables (set -u)
#   - Uses --break-system-packages flag for pip install
################################################################################
set -eu

NVM_VERSION="0.40.4"

sudo apt update
sudo apt install -y curl \
    tldr \
    bat \
    git \
    python3-full \
    python3-pip \
    jq \
    yq \
    net-tools \
    wget \
    gpg \
    netcat-openbsd \
    terminator \
    libfuse2 \
    gnome-control-center \
    gnome-online-accounts \
    nvtop \
    radeontop \
    btop \
    htop \
    tmux \
    nodejs \
    npm

# Python basics
pip install uv --break-system-packages

# nodejs nvm
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh" | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion