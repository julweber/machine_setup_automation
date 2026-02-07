#!/usr/bin/env bash
set -eu

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
    tmux

# Python basics
pip install uv --break-system-packages