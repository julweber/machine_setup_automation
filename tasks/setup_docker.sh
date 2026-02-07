#!/usr/bin/env bash
set -eu

#----------------- docker ----------------
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
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
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
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world