#!/usr/bin/env bash
################################################################################
# Script: setup_kubernetes.sh
# Description: Automates the installation and setup of a Kubernetes environment
#              using K3s (lightweight Kubernetes distribution) and K9s (terminal
#              UI for Kubernetes cluster management).
#
# Key Actions:
#   1. Updates system packages (apt update && upgrade)
#   2. Installs K3s cluster using the official installation script
#   3. Verifies K3s installation and service status
#   4. Installs K9s CLI tool for cluster management
#   5. Cleans up downloaded K9s package file
#
# Dependencies:
#   - curl: Required for downloading K3s installation script
#   - wget: Required for downloading K9s package
#   - apt: Package manager for installing K9s
#   - sudo: Root privileges required for installation
#   - systemctl: For managing K3s service
#
# Environment Variables:
#   - K9S_VERSION: K9s version to install (default: 0.50.7)
#
# Output:
#   - K3s kubeconfig location: /etc/rancher/k3s/k3s.yaml
#   - K9s CLI installed system-wide
#
# Usage:
#   ./setup_kubernetes.sh
#   K9S_VERSION=0.51.0 ./setup_kubernetes.sh  # Use specific K9s version
################################################################################
set -eu

# ----------------- k3s ------------------
# install k3s cluster
# Update system packages
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install K3s using official script
echo "Installing K3s..."
curl -sfL https://get.k3s.io | sudo sh -

# Verify installation
echo "Checking K3s status..."
sudo systemctl status k3s

# Output kubeconfig file path for cluster management
echo "K3s cluster is ready! Kubeconfig file location: /etc/rancher/k3s/k3s.yaml"
echo "You can use this file to manage the cluster from other machines."


# -------- k9s cli ------------
K9S_VERSION="${K9S_VERSION:-0.50.7}"
wget "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_linux_amd64.deb"
sudo apt install ./k9s_linux_amd64.deb
rm k9s_linux_amd64.deb
# --------------------------------