#!/usr/bin/env bash
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