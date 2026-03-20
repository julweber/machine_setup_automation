#!/usr/bin/env bash
# shellcheck disable=SC1091
#
# ==============================================================================
# hyprwhspr Installation Script
# ==============================================================================
#
# DESCRIPTION:
#   Installs and configures hyprwhspr — native Wayland speech-to-text dictation
#   for Linux. Handles system dependencies (including the ydotool 1.0+ backport
#   required on Ubuntu/Debian), clones the repository, and runs the automated
#   setup wizard.
#
# KEY ACTIONS:
#   1. Installs system apt packages required by hyprwhspr
#   2. Handles ydotool version enforcement (Ubuntu apt ships 0.1.x — broken;
#      silently upgrades to 1.0.4 from Debian backports)
#   3. Installs missing Python packages via pip
#   4. Clones or updates the hyprwhspr repository
#   5. Runs 'hyprwhspr setup auto' with flags derived from env variables
#   6. Prints post-install next-steps summary
#
# IMPORTANT VARIABLES:
#   HYPRWHSPR_INSTALL_DIR     - Clone destination (default: ~/hyprwhspr)
#   HYPRWHSPR_REPO_URL        - Git remote (default: github.com/goodroot/hyprwhspr)
#   HYPRWHSPR_BACKEND         - Backend: nvidia|vulkan|cpu|onnx-asr (default: auto)
#   HYPRWHSPR_MODEL           - Model name to download (default: setup wizard decides)
#   HYPRWHSPR_WAYBAR          - Enable Waybar integration (default: false — not used on GNOME)
#   HYPRWHSPR_MIC_OSD         - Enable mic visualiser overlay (default: true)
#   HYPRWHSPR_SYSTEMD         - Set up systemd services (default: true)
#   HYPRWHSPR_HYPR_BINDINGS   - Enable Hyprland compositor bindings (default: false)
#   HYPRWHSPR_SKIP_DEPS       - Skip apt + pip installation (default: false)
#   HYPRWHSPR_YDOTOOL_DEB_URL - ydotool 1.0.4 backport .deb URL
#
# DEPENDENCIES:
#   - Ubuntu 24.04 (apt-based)
#   - sudo privileges
#   - Internet connection
#   - Wayland session (GNOME/KDE/Hyprland/Sway) for runtime use
#   - Commands: apt, git, wget, python3, pip
#
# USAGE:
#   ./tasks/setup-hyprwhspr.sh
#   HYPRWHSPR_BACKEND=cpu HYPRWHSPR_WAYBAR=false ./tasks/setup-hyprwhspr.sh
#   HYPRWHSPR_SKIP_DEPS=true ./tasks/setup-hyprwhspr.sh
#
# NOTES:
#   - Log out and back in after first install for group permissions.
#   - Idempotent: safe to re-run (re-runs 'hyprwhspr setup auto' which is
#     itself idempotent per upstream docs).
#   - ydotool from Ubuntu apt (0.1.x) is INCOMPATIBLE — this script
#     automatically replaces it with 1.0.4 from Debian backports.
#
# ==============================================================================

set -eu

# === Colours ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[hyprwhspr]${NC} $1"; }
log_success() { echo -e "${GREEN}[hyprwhspr ✓]${NC} $1"; }
log_skip()    { echo -e "${YELLOW}[hyprwhspr ~]${NC} $1 (already present, skipping)"; }
log_warn()    { echo -e "${YELLOW}[hyprwhspr !]${NC} $1"; }
log_error()   { echo -e "${RED}[hyprwhspr ✗]${NC} $1"; }

# === Configuration ===
HYPRWHSPR_INSTALL_DIR="${HYPRWHSPR_INSTALL_DIR:-$HOME/hyprwhspr}"
HYPRWHSPR_REPO_URL="${HYPRWHSPR_REPO_URL:-https://github.com/goodroot/hyprwhspr.git}"
HYPRWHSPR_BACKEND="${HYPRWHSPR_BACKEND:-}"
HYPRWHSPR_MODEL="${HYPRWHSPR_MODEL:-}"
HYPRWHSPR_WAYBAR="${HYPRWHSPR_WAYBAR:-false}"
HYPRWHSPR_MIC_OSD="${HYPRWHSPR_MIC_OSD:-true}"
HYPRWHSPR_SYSTEMD="${HYPRWHSPR_SYSTEMD:-true}"
HYPRWHSPR_HYPR_BINDINGS="${HYPRWHSPR_HYPR_BINDINGS:-false}"
HYPRWHSPR_SKIP_DEPS="${HYPRWHSPR_SKIP_DEPS:-false}"
HYPRWHSPR_YDOTOOL_DEB_URL="${HYPRWHSPR_YDOTOOL_DEB_URL:-https://deb.debian.org/debian/pool/main/y/ydotool/ydotool_1.0.4-2~bpo13+1_amd64.deb}"

# === Banner ===
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  hyprwhspr — Speech-to-Text Dictation Setup${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# === Helper functions ===

# Returns 0 (true) if $1 >= $2
_version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Prints the installed ydotool version, or empty string if not installed
_get_ydotool_version() {
    if ! command -v ydotool &>/dev/null; then
        echo ""
        return 0
    fi
    # Prefer dpkg-query (most reliable for the *installed* version)
    local ver
    ver=$(dpkg-query -W -f='${Version}' ydotool 2>/dev/null || true)
    if [[ -n "$ver" ]]; then
        # Strip epoch (e.g. "2:") and debian revision (e.g. "-1ubuntu1")
        ver="${ver#*:}"
        ver="${ver%%-*}"
        echo "$ver"
        return 0
    fi
    # Fallback via ydotoold --version (may hang on 0.1.x, hence timeout)
    if command -v ydotoold &>/dev/null; then
        local out
        out=$(timeout 3s ydotoold --version 2>&1 || true)
        if [[ "$out" != "UNKNOWN" && "$out" =~ ([0-9]+\.[0-9]+\.?[0-9]*) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi
    # Cannot determine — assume old
    echo "0.1.0"
}

_install_ydotool_backport() {
    log_info "Installing ydotool 1.0.4 from Debian backports..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local deb_file="$tmp_dir/ydotool.deb"

    if ! wget -q --show-progress -O "$deb_file" "$HYPRWHSPR_YDOTOOL_DEB_URL"; then
        log_error "Failed to download ydotool .deb from $HYPRWHSPR_YDOTOOL_DEB_URL"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Remove old packages (old versions were split into ydotool + ydotoold)
    if dpkg -l ydotool &>/dev/null 2>&1; then
        log_info "Removing old ydotool..."
        sudo apt remove -y ydotool ydotoold 2>/dev/null \
            || sudo apt remove -y ydotool \
            || true
    fi

    sudo dpkg -i "$deb_file" || sudo apt install -f -y \
        || { log_error "dpkg install and apt fix-broken both failed for ydotool"; rm -rf "$tmp_dir"; return 1; }
    rm -rf "$tmp_dir"
    log_success "ydotool 1.0.4 installed"
}

# === System dependency installation ===

if [[ "$HYPRWHSPR_SKIP_DEPS" == "true" ]]; then
    log_skip "Dependency installation"
else
    # 2a. apt packages
    log_info "Updating apt package lists..."
    sudo apt update

    log_info "Installing core apt packages..."
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        git \
        cmake \
        make \
        build-essential \
        python3-dev \
        libportaudio2 \
        python3-numpy \
        python3-scipy \
        python3-evdev \
        python3-requests \
        python3-psutil \
        python3-rich \
        python3-pulsectl \
        python3-pyudev \
        python3-dbus \
        python3-gi \
        gir1.2-gtk-4.0 \
        pipewire \
        pipewire-pulse \
        pulseaudio-utils \
        wl-clipboard \
        wget

    log_success "Core apt packages installed"

    # Optional apt packages — warn but don't fail if unavailable
    OPTIONAL_APT_PACKAGES=(
        python3-sounddevice
        python3-pyperclip
        python3-websocket
    )

    for pkg in "${OPTIONAL_APT_PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null 2>&1; then
            sudo apt install -y "$pkg"
        else
            log_warn "apt package '$pkg' not found — will install via pip if needed"
        fi
    done

    # gtk4-layer-shell (required for the mic-osd visualiser)
    if apt-cache show gir1.2-gtk4layershell-1.0 &>/dev/null 2>&1; then
        sudo apt install -y gir1.2-gtk4layershell-1.0
        log_success "gtk4-layer-shell installed — mic-osd visualiser available"
    else
        log_warn "gir1.2-gtk4layershell-1.0 not found — mic-osd visualiser will be disabled"
        log_warn "Consider forcing --no-mic-osd or upgrading Ubuntu"
    fi

    # 2b. ydotool — must be >= 1.0.0; Ubuntu apt ships broken 0.1.x
    YDOTOOL_MIN_VERSION="1.0.0"
    CURRENT_YDOTOOL_VERSION=$(_get_ydotool_version)

    if [[ -z "$CURRENT_YDOTOOL_VERSION" ]]; then
        log_info "ydotool not found — installing from backports..."
        _install_ydotool_backport
    elif _version_gte "$CURRENT_YDOTOOL_VERSION" "$YDOTOOL_MIN_VERSION"; then
        log_skip "ydotool $CURRENT_YDOTOOL_VERSION (>= $YDOTOOL_MIN_VERSION required)"
    else
        log_warn "ydotool $CURRENT_YDOTOOL_VERSION is too old (< $YDOTOOL_MIN_VERSION)"
        log_info "Replacing with ydotool 1.0.4 from Debian backports..."
        _install_ydotool_backport
    fi

    # 2c. Python pip packages — only install what is missing
    PIP_PACKAGES=()
    python3 -c "import sounddevice"  2>/dev/null || PIP_PACKAGES+=(sounddevice)
    python3 -c "import pyperclip"    2>/dev/null || PIP_PACKAGES+=(pyperclip)
    python3 -c "import pulsectl"     2>/dev/null || PIP_PACKAGES+=(pulsectl)
    python3 -c "import pyudev"       2>/dev/null || PIP_PACKAGES+=(pyudev)
    python3 -c "import websocket"    2>/dev/null || PIP_PACKAGES+=("websocket-client")

    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        log_info "Installing pip packages: ${PIP_PACKAGES[*]}"
        python3 -m pip install --user --break-system-packages "${PIP_PACKAGES[@]}" \
            2>/dev/null \
            || python3 -m pip install --user "${PIP_PACKAGES[@]}"
        log_success "pip packages installed"
    else
        log_skip "pip packages (all already importable)"
    fi

    # Warn if dbus missing (cannot be pip-installed — must come from system)
    python3 -c "import dbus" 2>/dev/null \
        || log_warn "python3-dbus missing — install via: sudo apt install python3-dbus"
fi

# === Clone or update the repository ===

if [[ -d "$HYPRWHSPR_INSTALL_DIR/.git" ]]; then
    log_info "Updating hyprwhspr repository at $HYPRWHSPR_INSTALL_DIR ..."
    git -C "$HYPRWHSPR_INSTALL_DIR" pull --ff-only
    log_success "Repository updated"
else
    log_info "Cloning hyprwhspr to $HYPRWHSPR_INSTALL_DIR ..."
    git clone "$HYPRWHSPR_REPO_URL" "$HYPRWHSPR_INSTALL_DIR"
    log_success "Repository cloned"
fi

# === user role addition ===
if ! groups $USER | grep -q tty; then                                  
    echo "You are not in the tty group. Adding to group"    
    sudo usermod -aG tty $USER   
fi   
if ! groups $USER | grep -q audio; then                                  
    echo "You are not in the audio group. Adding to group"
    sudo usermod -aG audio $USER                          
fi      
if ! groups $USER | grep -q input; then                                  
    echo "You are not in the input group. Adding to group"
    sudo usermod -aG input $USER                             
fi                                                  

# === Run hyprwhspr setup auto (only if not already configured) ===

CONFIG_FILE="$HOME/.config/hyprwhspr/config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_info "Running hyprwhspr setup auto ..."

    SETUP_ARGS=()

    [[ -n "$HYPRWHSPR_BACKEND" ]]              && SETUP_ARGS+=(--backend "$HYPRWHSPR_BACKEND")
    [[ -n "$HYPRWHSPR_MODEL" ]]                && SETUP_ARGS+=(--model "$HYPRWHSPR_MODEL")
    [[ "$HYPRWHSPR_WAYBAR" == "true" ]]        || SETUP_ARGS+=(--no-waybar)
    [[ "$HYPRWHSPR_MIC_OSD" == "false" ]]      && SETUP_ARGS+=(--no-mic-osd)
    [[ "$HYPRWHSPR_SYSTEMD" == "false" ]]      && SETUP_ARGS+=(--no-systemd)
    [[ "$HYPRWHSPR_HYPR_BINDINGS" == "true" ]] && SETUP_ARGS+=(--hypr-bindings)

    "$HYPRWHSPR_INSTALL_DIR/bin/hyprwhspr" setup auto "${SETUP_ARGS[@]}"

    log_success "hyprwhspr setup complete"
else
    log_skip "Configuration file exists ($CONFIG_FILE) — skipping 'hyprwhspr setup auto' to avoid overriding user config"
fi

# === Add hyprwhspr/bin to PATH if not already present ===

HYPRWHSPR_BIN_PATH="$HOME/hyprwhspr/bin"
if ! grep -q "$HYPRWHSPR_BIN_PATH" "$HOME/.profile" 2>/dev/null; then
    echo "# hyprwhspr binary path" >> "$HOME/.profile"
    echo "export PATH=\"$PATH:$HYPRWHSPR_BIN_PATH\"" >> "$HOME/.profile"
fi

# === Post-install summary ===

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  hyprwhspr installed successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Next steps:"
echo ""
echo -e "  ${YELLOW}1. Log out and back in${NC} for group permissions to take effect."
echo ""
echo "  2. Verify the installation:"
echo "     hyprwhspr status"
echo ""
echo "  3. Start dictating:"
echo -e "     Press ${BLUE}Super+Alt+D${NC} to start / stop dictation."
echo ""
echo " Daemon controls:"
echo "     systemctl --user status hyprwhspr # daemon status"
echo "     systemctl --user restart hyprwhspr # restart daemon"
echo " Configuration file:"
echo "     $HOME/.config/hyprwhspr/config.json"
echo " Configuration schema:"
echo "     https://raw.githubusercontent.com/goodroot/hyprwhspr/main/share/config.schema.json"
echo ""
echo " For non hyprland users -> Configure your keyboard shortcut in your desktop manager:"
echo "     Command: $HYPRWHSPR_INSTALL_DIR/bin/hyprwhspr record toggle"
echo ""
echo "  Troubleshoot:"
echo "     journalctl --user -u hyprwhspr.service"
echo "     journalctl --user -u ydotool.service"
echo ""
echo "  Available hyprwhspr commands:"
$HYPRWHSPR_INSTALL_DIR/bin/hyprwhspr --help
