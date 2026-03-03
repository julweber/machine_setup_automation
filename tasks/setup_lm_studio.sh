#!/usr/bin/env bash
#
# ============================================================================
# LM Studio Installation Script
# ============================================================================
#
# DESCRIPTION:
#   Automates the installation and setup of LM Studio on Linux systems.
#   Downloads the AppImage binary, creates startup scripts, and configures
#   desktop integration. Optionally installs the llmster CLI tool (lms).
#
# KEY ACTIONS:
#   1. Detects the latest LM Studio version by following redirects from the
#      official download URL (unless a specific version is provided)
#   2. Creates a startup script (~/lmstudio) that launches the AppImage
#      with --no-sandbox flag
#   3. Creates a desktop shortcut (~/Desktop/LM-Studio.desktop) for easy access
#   4. Downloads the LM Studio AppImage binary to ~/lmstudio_bin
#   5. Backs up existing installation if present (to ~/lmstudio_bin_backup)
#   6. Optionally installs llmster CLI tool via official install script
#
# IMPORTANT VARIABLES:
#   LM_STUDIO_VERSION         - Version to install (default: auto-detect latest)
#   INSTALL_LLMSTER_ENABLED   - Install llmster CLI (default: true)
#   DEFAULT_LM_STUDIO_VERSION - Fallback version (0.4.6-1)
#   LATEST_URL                - URL to detect latest version
#   START_SCRIPT_TARGET_PATH  - Path to startup script (~/lmstudio)
#   APP_IMAGE_TARGET_PATH     - Path to AppImage binary (~/lmstudio_bin)
#   DESKTOP_LINK_TARGET_PATH  - Path to desktop shortcut (~/Desktop/LM-Studio.desktop)
#
# DEPENDENCIES:
#   - curl: For downloading and version detection
#   - wget: For downloading the AppImage
#   - grep: For parsing version from URLs
#   - Standard bash utilities (cat, chmod, mv)
#
# USAGE:
#   ./setup_lm_studio.sh
#   LM_STUDIO_VERSION=0.4.5-2 ./setup_lm_studio.sh
#   INSTALL_LLMSTER_ENABLED=false ./setup_lm_studio.sh
#
# ============================================================================

set -eu

# === Configuration ===
DESKTOP_LINK_TARGET_PATH="$HOME/Desktop/LM-Studio.desktop"
START_SCRIPT_TARGET_PATH="$HOME/lmstudio"
APP_IMAGE_TARGET_PATH="$HOME/lmstudio_bin"
APP_IMAGE_BACKUP_PATH="$HOME/lmstudio_bin_backup"

INSTALL_LLMSTER_ENABLED="${INSTALL_LLMSTER_ENABLED:-true}"

LATEST_URL="https://lmstudio.ai/download/latest/linux/x64"

DEFAULT_LM_STUDIO_VERSION="0.4.6-1"

LM_STUDIO_VERSION="${LM_STUDIO_VERSION:-$DEFAULT_LM_STUDIO_VERSION}"
SOURCE_URL="https://installers.lmstudio.ai/linux/x64/$LM_STUDIO_VERSION/LM-Studio-$LM_STUDIO_VERSION-x64.AppImage"


# === check if not specified directly ===
if [[ "$LM_STUDIO_VERSION" == "$DEFAULT_LM_STUDIO_VERSION" ]]; then
    echo "Checking latest LM Studio version..."

    # Follow redirects and grab the final URL, which contains the version number
    FINAL_URL=$(curl -sI -L "$LATEST_URL" -o /dev/null -w '%{url_effective}')

    # Extract version from the URL (e.g. .../LM-Studio-0.3.5-x86_64.AppImage)
    LM_STUDIO_VERSION=$(echo "$FINAL_URL" | grep -oP -m1 '[\d]+\.[\d]+\.[\d]+-[\d]+' | head -1)

    echo "Latest LM Studio version: $LM_STUDIO_VERSION"
    echo "Download URL: $FINAL_URL"
    SOURCE_URL="$FINAL_URL"
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

chmod +x "$START_SCRIPT_TARGET_PATH"

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

chmod +x "$DESKTOP_LINK_TARGET_PATH"

if [[ -f "$APP_IMAGE_TARGET_PATH" ]]; then
    echo "LM Studio binary exists: $APP_IMAGE_TARGET_PATH"
    echo "Moving to $APP_IMAGE_BACKUP_PATH"
    mv "$APP_IMAGE_TARGET_PATH" "$APP_IMAGE_BACKUP_PATH"
fi

echo "Downloading LM Studio AppImage from: $SOURCE_URL to $APP_IMAGE_TARGET_PATH ... " 
wget "$SOURCE_URL" --output-document "$APP_IMAGE_TARGET_PATH"
chmod +x "$APP_IMAGE_TARGET_PATH"
echo "Finished installing version: $LM_STUDIO_VERSION"

set +e

# install llmster cli (lms)
if [[ "$INSTALL_LLMSTER_ENABLED" == "true" ]]; then
    echo "Installing llmster . NOT FAILING SCRIPT ON ERRORS!!!"
    curl -fsSL https://lmstudio.ai/install.sh | bash
    lms --help
    lms --version
    echo "Finished install llmster."
    echo
else
    echo "llmster install is disabled. Skipping installation."
    echo
fi
