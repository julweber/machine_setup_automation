#!/usr/bin/env bash
set -eu

# === Configuration ===

LM_STUDIO_VERSION="0.4.1-1"
SOURCE_URL="https://installers.lmstudio.ai/linux/x64/$LM_STUDIO_VERSION/LM-Studio-$LM_STUDIO_VERSION-x64.AppImage"

DESKTOP_LINK_TARGET_PATH="$HOME/Desktop/LM-Studio.desktop"
START_SCRIPT_TARGET_PATH="$HOME/lmstudio"
APP_IMAGE_TARGET_PATH="$HOME/lmstudio_bin"
APP_IMAGE_BACKUP_PATH="$HOME/lmstudio_bin_backup"

INSTALL_LLMSTER_ENABLED="true"
# install llmster cli (lms)
if [[ "$INSTALL_LLMSTER_ENABLED" == "true" ]]; then
    echo "Installing llmster ..."
    curl -fsSL https://lmstudio.ai/install.sh | bash
    lms --help
    lms --version
    echo "Finished install llmster."
    echo
else
    echo "llmster install is disabled. Skipping installation."
    echo
fi

echo "Installing version: $LM_STUDIO_VERSION"

# create start script
if [[ -f "$START_SCRIPT_TARGET_PATH" ]]; then
    echo "Start script exists at: $START_SCRIPT_TARGET_PATH . Skipping creation."
else
    echo "Creating start script at: $START_SCRIPT_TARGET_PATH ..."
    cat > "$START_SCRIPT_TARGET_PATH" << EOF
#!/usr/bin/env bash
cd \$HOME
./lmstudio_bin --no-sandbox
EOF
fi

chmod +x $START_SCRIPT_TARGET_PATH

# create desktop link
if [[ -f "$DESKTOP_LINK_TARGET_PATH" ]]; then
    echo "desktop link exists at: $DESKTOP_LINK_TARGET_PATH . Skipping creation."
else
    echo "Creating desktop link at: $DESKTOP_LINK_TARGET_PATH ..."
    cat > "$DESKTOP_LINK_TARGET_PATH" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=LM Studio
Comment=LM Studio
Icon=utilities-terminal
Exec=$START_SCRIPT_TARGET_PATH
EOF
fi

chmod +x $DESKTOP_LINK_TARGET_PATH

if [[ -f "$APP_IMAGE_TARGET_PATH" ]]; then
    echo "LM Studio binary exists: $APP_IMAGE_TARGET_PATH"
    echo "Moving to $APP_IMAGE_BACKUP_PATH"
    mv $APP_IMAGE_TARGET_PATH $APP_IMAGE_BACKUP_PATH
fi

echo "Downloading LM Studio AppImage from: $SOURCE_URL to $APP_IMAGE_TARGET_PATH ... " 
wget $SOURCE_URL --output-document $APP_IMAGE_TARGET_PATH
chmod +x $APP_IMAGE_TARGET_PATH
echo "Finished installing version: $LM_STUDIO_VERSION"

