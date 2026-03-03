#!/usr/bin/env bash
# shellcheck disable=SC1091
#
# ==============================================================================
# Docker Installation Script for Ubuntu
# ==============================================================================
#
# DESCRIPTION:
#   Installs Docker Engine and related components on Ubuntu systems.
#   Checks for existing Docker installation, removes conflicting packages,
#   adds official Docker repository, and configures user permissions.
#
# KEY ACTIONS:
#   1. Checks if Docker is already installed (exits early if found)
#   2. Updates system packages (apt update && upgrade)
#   3. Installs prerequisites (ca-certificates, curl)
#   4. Removes old/conflicting Docker packages (docker.io, podman-docker, etc.)
#   5. Adds Docker's official GPG key to /etc/apt/keyrings/
#   6. Configures Docker's official APT repository
#   7. Installs Docker Engine components:
#      - docker-ce (Docker Community Edition)
#      - docker-ce-cli (Docker CLI)
#      - containerd.io (Container runtime)
#      - docker-buildx-plugin (Build extension)
#      - docker-compose-plugin (Docker Compose v2)
#   8. Verifies installation with 'hello-world' container
#   9. Configures docker group and adds current user
#   10. Sets permissions on /var/run/docker.sock
#
# DEPENDENCIES:
#   - Ubuntu-based Linux distribution
#   - sudo privileges required
#   - Internet connection for downloading packages
#   - Commands: apt, curl, dpkg, lsb_release
#
# VARIABLES:
#   - USER: Current username (used for group membership)
#   - UBUNTU_VERSION: Detected Ubuntu version for logging
#
# USAGE:
#   ./setup_docker.sh
#
# NOTE:
#   After running, you may need to log out and back in for group changes
#   to take effect, or run 'newgrp docker' to activate the docker group.
#
# ==============================================================================

set -eu

#----------------- docker ----------------
# Check if Docker is already installed
if command -v docker &> /dev/null && docker --version &> /dev/null; then
    echo "Docker is already installed"
    exit 0
fi

# Update package lists
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl 

# Remove old Docker packages
echo "Removing existing Docker packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Add Docker GPG key and repository
echo "Setting up Docker repository..."

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(source /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker Engine
echo "Installing Docker Engine..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
echo "Testing Docker installation..."
sudo docker run hello-world

UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "24.04")
echo "Docker installed successfully on Ubuntu $UBUNTU_VERSION"

sudo groupadd docker
sudo chown root:docker /var/run/docker.sock
sudo usermod -aG docker "$USER"
newgrp docker
docker run hello-world