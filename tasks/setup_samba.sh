#!/usr/bin/env bash
set -eu

# ---------------- samba --------------------

# Variables (customize as needed)
BASE_SHARE_PATH="/home/samba"
SAMBA_SHARE_NAME="shared"
SHARE_PATH="$BASE_SHARE_PATH/shared"
SAMBA_USER="sambauser"
DEVELOPER_GROUP_NAME="devs"

sudo mkdir -p "$BASE_SHARE_PATH"
sudo mkdir -p "$SHARE_PATH"

sudo groupadd "$DEVELOPER_GROUP_NAME"
sudo chown "$SAMBA_USER":devs "$BASE_SHARE_PATH"
sudo chmod -R 770 "$BASE_SHARE_PATH"

sudo chown "$SAMBA_USER":devs "$SHARE_PATH"
sudo chmod -R 770 "$SHARE_PATH"

sudo usermod -aG "$DEVELOPER_GROUP_NAME" "$SAMBA_USER"
sudo usermod -aG "$DEVELOPER_GROUP_NAME" "$USER"
newgrp devs



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