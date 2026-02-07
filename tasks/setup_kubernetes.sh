#!/usr/bin/env bash
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