#!/usr/bin/env bash
################################################################################
# SAMBA SHARE SETUP SCRIPT
################################################################################
#
# DESCRIPTION:
#   This script automates the installation and configuration of a Samba file
#   sharing server on Debian/Ubuntu systems. It creates a shared directory
#   accessible over the network with proper permissions and user authentication.
#
# KEY ACTIONS:
#   1. Creates base share directory structure and developer group
#   2. Sets up proper ownership and permissions (770) for share paths
#   3. Installs Samba package via apt
#   4. Enables and starts the smbd service
#   5. Backs up original Samba configuration
#   6. Adds share definition to /etc/samba/smb.conf
#   7. Creates Samba user (if doesn't exist) with no-login system account
#   8. Prompts for Samba password configuration
#   9. Displays network access information
#
# IMPORTANT VARIABLES:
#   BASE_SHARE_PATH      - Root directory for Samba shares (/home/samba)
#   SAMBA_SHARE_NAME     - Name of the share visible on network (shared)
#   SHARE_PATH           - Full path to shared directory
#   SAMBA_USER           - System user for Samba authentication (sambauser)
#   DEVELOPER_GROUP_NAME - Group with access to shares (devs)
#
# DEPENDENCIES:
#   - apt package manager (Debian/Ubuntu)
#   - sudo privileges
#   - samba package
#   - systemd (for service management)
#
# SIDE EFFECTS:
#   - Modifies /etc/samba/smb.conf (creates backup first)
#   - Creates system user and group
#   - Adds current user to developer group
#   - Opens network share (SMB protocol, typically port 445)
#
################################################################################
set -eu

# ---------------- samba --------------------

# Variables (customize as needed)
BASE_SHARE_PATH="/home/samba"
SAMBA_SHARE_NAME="shared"
SHARE_PATH="$BASE_SHARE_PATH/shared"
SAMBA_USER="sambauser"
DEVELOPER_GROUP_NAME="devs"

# Create developer group if it doesn't exist (idempotent)
if ! getent group "$DEVELOPER_GROUP_NAME" >/dev/null 2>&1; then
    sudo groupadd "$DEVELOPER_GROUP_NAME"
fi

# Create Samba user if it doesn't exist (idempotent)
if ! id -u "$SAMBA_USER" >/dev/null 2>&1; then
    sudo adduser --no-create-home --disabled-password --gecos "" "$SAMBA_USER"
fi

# Add users to developer group (idempotent - usermod handles existing membership gracefully)
sudo usermod -aG "$DEVELOPER_GROUP_NAME" "$SAMBA_USER"
sudo usermod -aG "$DEVELOPER_GROUP_NAME" "$USER"

# Set ownership on directories (now that user exists!)
sudo chown "$SAMBA_USER":devs "$BASE_SHARE_PATH"
sudo chmod -R 770 "$BASE_SHARE_PATH"

sudo chown "$SAMBA_USER":devs "$SHARE_PATH"
sudo chmod -R 770 "$SHARE_PATH"



# 1. Update package list and install Samba
sudo apt update
sudo apt install samba -y

# 2. Enable and start the Samba service
sudo systemctl enable smbd
sudo systemctl start smbd

# 3. Create the shared directory and set permissions
# sudo mkdir -p "$SHARE_PATH"
# sudo chown "$USER":"$USER" "$SHARE_PATH"

# 4. Backup the original Samba config
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# 5. Add Samba share definition to smb.conf
sudo bash -c "cat >> /etc/samba/smb.conf <<EOL

[$SAMBA_SHARE_NAME]
   path = $SHARE_PATH
   read only = no
   browsable = yes
EOL
"

# 6. Restart Samba to apply changes
sudo systemctl restart smbd

# 7. Add a new system user if it doesn't exist
if ! id -u "$SAMBA_USER" >/dev/null 2>&1; then
    sudo adduser --no-create-home --disabled-password --gecos "" "$SAMBA_USER"
    sudo usermod -aG "$DEVELOPER_GROUP_NAME" "$SAMBA_USER"
fi

# 8. Set Samba password for the user
echo "Set Samba password for user $SAMBA_USER:"
sudo smbpasswd -a "$SAMBA_USER"

echo "Samba has been installed and configured."
echo "Share path: $SHARE_PATH"
printf 'Access it on the network as: \\\\\\%s\\\%s\n' "$(hostname -I | awk '{print $1}')" "$SAMBA_SHARE_NAME"

# ---------------------------------