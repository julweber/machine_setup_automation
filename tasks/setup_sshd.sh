#!/usr/bin/env bash
#
# SSH Server (sshd) Setup Script
# ===============================
#
# DESCRIPTION:
#   Installs and configures OpenSSH server with security-hardened settings.
#   Sets up the SSH daemon to use public key authentication only, disables
#   password authentication, and configures a custom port.
#
# KEY ACTIONS:
#   1. Installs openssh-server package via apt
#   2. Displays current sshd service status
#   3. Configures sshd with security settings:
#      - Enables public key authentication
#      - Disables password authentication
#      - Sets custom SSH port
#   4. Appends configuration lines to sshd_config (idempotent - checks before adding)
#   5. Enables and restarts SSH service
#   6. Creates ~/.ssh directory and authorized_keys file
#
# IMPORTANT VARIABLES:
#   SSHD_PORT          - SSH daemon port (default: 2224)
#   SSHD_CONFIG_FILE   - Path to sshd config (default: /etc/ssh/sshd_config)
#
# DEPENDENCIES:
#   - apt package manager
#   - sudo privileges
#   - systemctl (systemd)
#
# USAGE:
#   SSHD_PORT=2224 ./setup_sshd.sh
#
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
mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"

echo "Place your allowed public keys in: $HOME/.ssh/authorized_keys"
echo "----- FINISHED SSH SETUP ------"