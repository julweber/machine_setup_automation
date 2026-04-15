#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-docker.sh — Install Docker Engine
# =============================================================================
#
# Description:
#   Installs Docker Engine and related components on Ubuntu systems.
#
# Options:
#   --force   Skip the Docker installed check and force reinstallation
#   --help    Show help message
#
# Usage:
#   ./setup-docker.sh
#   ./setup-docker.sh --force
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
FORCE=false
DOCKER_APT_KEY_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_KEY_PATH="/etc/apt/keyrings/docker.asc"
DOCKER_LIST_PATH="/etc/apt/sources.list.d/docker.list"
DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"

declare -a DOCKER_PACKAGES=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
)

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --force   Skip the Docker installed check and force reinstallation"
      echo "  --help    Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# =============================================================================
# Main
# =============================================================================

step "Setting up Docker"

# Check if Docker is already installed
if [[ "${FORCE}" == false ]] && command -v docker &>/dev/null && docker --version &>/dev/null; then
  success "Docker is already installed: $(docker --version)"
  exit 0
fi

info "Installing Docker..."

# Update and install prerequisites
step "Updating package lists and installing prerequisites"
sudo apt update
sudo apt install -y ca-certificates curl

# Remove old Docker packages
step "Removing existing Docker packages"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  if dpkg -l "$pkg" &>/dev/null; then
    info "Removing $pkg"
    sudo apt-get remove -y "$pkg" 2>/dev/null || true
  fi
done

# Add Docker GPG key
step "Setting up Docker GPG key"
sudo install -m 0755 -d /etc/apt/keyrings
if [[ -f "${DOCKER_KEY_PATH}" ]]; then
  info "GPG key already exists at ${DOCKER_KEY_PATH}"
else
  sudo curl -fsSL "${DOCKER_APT_KEY_URL}" -o "${DOCKER_KEY_PATH}"
  sudo chmod a+r "${DOCKER_KEY_PATH}"
fi

# Add Docker repository
step "Adding Docker repository"
# shellcheck disable=SC1091
UBUNTU_CODENAME=$(source /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
echo "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEY_PATH}] ${DOCKER_REPO_URL} ${UBUNTU_CODENAME} stable" \
  | sudo tee "${DOCKER_LIST_PATH}" > /dev/null
sudo apt-get update

# Install Docker Engine
step "Installing Docker Engine"
sudo apt install -y "${DOCKER_PACKAGES[@]}"

# Ensure docker group exists
step "Configuring docker group"
if getent group docker >/dev/null; then
  info "docker group already exists"
else
  sudo groupadd docker
fi
sudo chown root:docker /var/run/docker.sock 2>/dev/null || true
sudo usermod -aG docker "${USER}"

# Verify group membership
if id -nG | grep -q docker; then
  info "User already in docker group"
else
  newgrp docker >/dev/null 2>&1 || true
fi

# Verify installation
step "Testing Docker installation"
docker run hello-world

UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
success "Docker installed successfully on Ubuntu ${UBUNTU_VERSION}"
info "You may need to log out and back in for group changes to take effect"