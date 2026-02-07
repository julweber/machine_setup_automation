#!/usr/bin/env bash
set -eu


# Setup sshd server
sudo apt update
sudo apt install -y openssh-server

# show sshd status
echo "SSHD status:"
sudo systemctl status sshd |true
echo "--------------------"

# SSHD
# ------------ Config --------------
SSHD_PORT="${SSHD_PORT:-2224}"
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

echo "Configured env vars:"
echo "SSHD_PORT=$SSHD_PORT"
echo "SSHD_CONFIG_FILE=$SSHD_CONFIG_FILE"
echo "--------------------------"
echo ""


# Lines to ensure are in the config file (with variable substitution)
lines=(
    "PubkeyAuthentication yes"
    "PasswordAuthentication no"
    "Port $SSHD_PORT"
)

# Loop through each line and append it if not found
for line in "${lines[@]}"; do
    if ! sudo grep -q "^$line$" "$SSHD_CONFIG_FILE"; then
        echo "Line: '$line' not found in sshd configuration. Appending: $line"
        echo "$line" | sudo tee -a $SSHD_CONFIG_FILE
    else
        echo "'$line' is already present in $SSHD_CONFIG_FILE. Skipping insertion ..."
    fi
done

echo "sshd Configuration at: $SSHD_CONFIG_FILE"
sudo cat $SSHD_CONFIG_FILE

echo "Configuration has been checked and added to $SSHD_CONFIG_FILE if not present."

sudo systemctl enable --now ssh
# sudo systemctl status ssh
sudo systemctl restart ssh
# sudo systemctl status ssh

# prepare .ssh dir
mkdir -p $HOME/.ssh
touch $HOME/.ssh/authorized_keys

echo "Place your allowed public keys in: $HOME/.ssh/authorized_keys"
echo "----- FINISHED SSH SETUP ------"