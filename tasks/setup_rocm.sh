#!/usr/bin/env bash
###############################################################################
# ROCm Installation Script
#
# Description:
#   Installs AMD ROCm (Radeon Open Compute) platform for GPU computing on
#   Ubuntu systems. This script sets up the ROCm 7.0 alpha2 repositories,
#   configures necessary user permissions, and installs the ROCm software stack.
#
# Key Actions:
#   1. Installs Python build dependencies (setuptools, wheel)
#   2. Adds current user to 'render' and 'video' groups for GPU access
#   3. Downloads and installs ROCm GPG signing key
#   4. Configures APT repositories for ROCm 7.0 alpha2 and graphics drivers
#   5. Sets repository priority pinning for ROCm packages
#   6. Updates package lists and installs ROCm
#
# Dependencies:
#   - Ubuntu Noble (24.04) - specified in repository configuration
#   - wget - for downloading GPG keys
#   - gpg - for key verification
#   - sudo access - required for system-level installation
#
# Important Variables:
#   - $LOGNAME - Current user's login name, used for group membership
#   - ROCm version: 7.0_alpha2
#   - Target architecture: amd64
#
# Notes:
#   - Script uses 'set -eu' for strict error handling
#   - Commented-out sections show alternative installation method using
#     amdgpu-install package (version 6.4.1)
#   - User must log out and back in for group membership changes to take effect
#
###############################################################################
set -eu

# rocm installation
# wget https://repo.radeon.com/amdgpu-install/6.4.1/ubuntu/noble/amdgpu-install_6.4.60401-1_all.deb
# sudo apt install ./amdgpu-install_6.4.60401-1_all.deb
# sudo apt update
# sudo apt install -y python3-setuptools python3-wheel
# sudo usermod -a -G render,video $LOGNAME # Add the current user to the render and video groups
# sudo apt install rocm
# 
# sudo apt install -y "linux-headers-$(uname -r)" "linux-modules-extra-$(uname -r)"
# sudo apt install -y amdgpu-dkms
#
#
sudo apt install python3-setuptools python3-wheel -y
sudo usermod -a -G render,video "$LOGNAME"
sudo mkdir --parents --mode=0755 /etc/apt/keyrings
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.0_alpha2 noble main" | sudo tee /etc/apt/sources.list.d/rocm.list
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.0_alpha2/ubuntu noble main" | sudo tee /etc/apt/sources.list.d/rocm-graphics.list
echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' | sudo tee /etc/apt/preferences.d/rocm-pin-600
sudo apt update
sudo apt install rocm