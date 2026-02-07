#!/usr/bin/env bash
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
sudo usermod -a -G render,video $LOGNAME
sudo mkdir --parents --mode=0755 /etc/apt/keyrings
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.0_alpha2 noble main" | sudo tee /etc/apt/sources.list.d/rocm.list
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.0_alpha2/ubuntu noble main" | sudo tee /etc/apt/sources.list.d/rocm-graphics.list
echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' | sudo tee /etc/apt/preferences.d/rocm-pin-600
sudo apt update
sudo apt install rocm