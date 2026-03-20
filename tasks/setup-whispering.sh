#!/usr/bin/env bash
#
# ============================================================================
# Whispering Installation Script
# ============================================================================
#
# DESCRIPTION:
#   Automates the installation and setup of Whispering on Linux systems.
#   Downloads the AppImage binary, creates startup scripts, and configures
#   desktop integration.
#
# KEY ACTIONS:
#   1. Creates a startup script (~/whispering) that launches the AppImage
#      with --no-sandbox flag
#   2. Creates a desktop shortcut (~/Desktop/Whispering.desktop) for easy access
#   3. Downloads the Whispering AppImage binary to ~/whispering_bin
#   4. Backs up existing installation if present (to ~/whispering_bin_backup)
#
# IMPORTANT VARIABLES:
#   WHISPERING_VERSION        - Version to install (default: 7.5.1)
#   START_SCRIPT_TARGET_PATH  - Path to startup script (~/whispering)
#   APP_IMAGE_TARGET_PATH     - Path to AppImage binary (~/whispering_bin)
#   DESKTOP_LINK_TARGET_PATH  - Path to desktop shortcut (~/Desktop/Whispering.desktop)
#
# DEPENDENCIES:
#   - wget: For downloading the AppImage
#   - Standard bash utilities (cat, chmod, mv)
#
# USAGE:
#   ./setup-whispering.sh
#   WHISPERING_VERSION=7.6.0 ./setup-whispering.sh
#
# ============================================================================

set -eu

# === Configuration ===
WHISPERING_VERSION="${WHISPERING_VERSION:-7.11.0}"

SOURCE_URL="https://github.com/EpicenterHQ/epicenter/releases/download/v${WHISPERING_VERSION}/Whispering_${WHISPERING_VERSION}_amd64.AppImage"

DESKTOP_LINK_TARGET_PATH="$HOME/Desktop/Whispering.desktop"
START_SCRIPT_TARGET_PATH="$HOME/whispering"
APP_IMAGE_TARGET_PATH="$HOME/whispering_bin"
APP_IMAGE_BACKUP_PATH="$HOME/whispering_bin_backup"

echo "Installing Whispering version: $WHISPERING_VERSION"

# create start script
if [[ -f "$START_SCRIPT_TARGET_PATH" ]]; then
    echo "Start script exists at: $START_SCRIPT_TARGET_PATH . Skipping creation."
else
    echo "Creating start script at: $START_SCRIPT_TARGET_PATH ..."
    cat > "$START_SCRIPT_TARGET_PATH" << EOF
#!/usr/bin/env bash
cd \$HOME
./whispering_bin --no-sandbox
EOF
fi

chmod +x "$START_SCRIPT_TARGET_PATH"

# create desktop link
if [[ -f "$DESKTOP_LINK_TARGET_PATH" ]]; then
    echo "Desktop link exists at: $DESKTOP_LINK_TARGET_PATH . Skipping creation."
else
    echo "Creating desktop link at: $DESKTOP_LINK_TARGET_PATH ..."
    cat > "$DESKTOP_LINK_TARGET_PATH" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=Whispering
Comment=Whispering
Icon=utilities-terminal
Exec=$START_SCRIPT_TARGET_PATH
EOF
fi

chmod +x "$DESKTOP_LINK_TARGET_PATH"

if [[ -f "$APP_IMAGE_TARGET_PATH" ]]; then
    echo "Whispering binary exists: $APP_IMAGE_TARGET_PATH"
    echo "Moving to $APP_IMAGE_BACKUP_PATH"
    mv "$APP_IMAGE_TARGET_PATH" "$APP_IMAGE_BACKUP_PATH"
fi

echo "Downloading Whispering AppImage from: $SOURCE_URL to $APP_IMAGE_TARGET_PATH ..."
wget "$SOURCE_URL" --output-document "$APP_IMAGE_TARGET_PATH"
chmod +x "$APP_IMAGE_TARGET_PATH"
echo "Finished installing Whispering version: $WHISPERING_VERSION"
