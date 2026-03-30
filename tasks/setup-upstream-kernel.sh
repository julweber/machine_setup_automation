#!/usr/bin/env bash
# =============================================================================
# setup-upstream-kernel.sh
# Prepares the Zabbly mainline kernel apt repo on Ubuntu 22.04 / 24.04 LTS
# https://pkgs.zabbly.com/kernel/stable
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Helpers ───────────────────────────────────────────────────────────────────
check_supported_distro() {
    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect OS. /etc/os-release not found."
    fi
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        die "This script is intended for Ubuntu only (detected: $ID)."
    fi
    case "$VERSION_CODENAME" in
        noble|jammy) ;;
        *) warn "Unsupported Ubuntu release '$VERSION_CODENAME'. Zabbly officially supports noble (24.04) and jammy (22.04). Proceeding anyway..." ;;
    esac
    info "Detected Ubuntu ${VERSION_ID} (${VERSION_CODENAME})"
}

check_secure_boot() {
    if command -v mokutil &>/dev/null; then
        if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
            warn "Secure Boot is ENABLED."
            warn "Zabbly kernels are unsigned and will NOT boot with Secure Boot on."
            warn "Disable Secure Boot in your BIOS/UEFI before rebooting, or enroll a Machine Owner Key."
            echo
            read -rp "Continue anyway? [y/N] " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted by user."; exit 0; }
        else
            success "Secure Boot is disabled — good to go."
        fi
    else
        warn "mokutil not found; cannot check Secure Boot status. Proceeding."
    fi
}

check_nvidia() {
    if lsmod 2>/dev/null | grep -q "^nvidia"; then
        warn "NVIDIA kernel module detected."
        warn "Mainline kernels may break NVIDIA proprietary drivers until DKMS rebuilds them."
        echo
        read -rp "Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted by user."; exit 0; }
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║   Zabbly Mainline Kernel Repository Setup    ║${RESET}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo

    check_supported_distro
    check_secure_boot
    check_nvidia

    # ── Step 1: Dependencies ─────────────────────────────────────────────────
    info "Installing dependencies (curl, apt-transport-https)..."
    sudo apt-get install -y --quiet curl apt-transport-https ca-certificates
    success "Dependencies installed."

    # ── Step 2: Keyring ──────────────────────────────────────────────────────
    KEYRING_DIR="/etc/apt/keyrings"
    KEYRING_FILE="${KEYRING_DIR}/zabbly.asc"

    if [[ -f "$KEYRING_FILE" ]]; then
        info "Keyring already exists at ${KEYRING_FILE}"
    else
        info "Creating keyring directory: ${KEYRING_DIR}"
        sudo mkdir -p "$KEYRING_DIR"

        info "Fetching Zabbly signing key..."
        curl -fsSL https://pkgs.zabbly.com/key.asc \
            | sudo tee "$KEYRING_FILE" > /dev/null \
            || die "Failed to download Zabbly signing key. Check your internet connection."
        sudo chmod 644 "$KEYRING_FILE"
        success "Signing key saved to ${KEYRING_FILE}."
    fi

    # ── Step 3: Repository ───────────────────────────────────────────────────
    SOURCES_FILE="/etc/apt/sources.list.d/zabbly-kernel-stable.sources"
    source /etc/os-release  # re-source to get VERSION_CODENAME cleanly

    if [[ -f "$SOURCES_FILE" ]]; then
        info "Repository file already exists at ${SOURCES_FILE}"
        CURRENT_SUITE=$(grep "^Suites:" "$SOURCES_FILE" | awk '{print $2}')
        if [[ "$CURRENT_SUITE" == "$VERSION_CODENAME" ]]; then
            success "Repository already configured for suite '${VERSION_CODENAME}'."
        else
            warn "Repository configured for '${CURRENT_SUITE}', updating to '${VERSION_CODENAME}'."
            cat <<EOF | sudo tee "$SOURCES_FILE" > /dev/null
Enabled: yes
Types: deb deb-src
URIs: https://pkgs.zabbly.com/kernel/stable
Suites: ${VERSION_CODENAME}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: ${KEYRING_FILE}
EOF
            success "Repository updated for suite '${VERSION_CODENAME}'."
        fi
    else
        info "Writing repository source file: ${SOURCES_FILE}"
        cat <<EOF | sudo tee "$SOURCES_FILE" > /dev/null
Enabled: yes
Types: deb deb-src
URIs: https://pkgs.zabbly.com/kernel/stable
Suites: ${VERSION_CODENAME}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: ${KEYRING_FILE}
EOF
        success "Repository configured for suite '${VERSION_CODENAME}'."
    fi

    # ── Step 4: Update package index ─────────────────────────────────────────
    info "Updating package index..."
    sudo apt-get update -q || die "apt-get update failed."
    success "Package index updated."

    # ── Step 5: Print installation instructions ───────────────────────────────
    echo
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
    success "Repository setup complete!"
    info "Currently running : $(uname -r)"
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
    echo
    info "To list available Zabbly kernels:"
    echo -e "  ${CYAN}apt-cache search linux-zabbly${RESET}"
    echo
    info "To install a specific kernel version:"
    echo -e "  ${CYAN}sudo apt-get install <package-name>${RESET}"
    echo
    info "Example:"
    echo -e "  ${CYAN}apt-cache search linux-zabbly | grep mainline${RESET}"
    echo -e "  ${CYAN}sudo apt-get install linux-zabbly-6.8.0-mainline${RESET}"
    echo
    info "To view all installed kernels:"
    echo -e "  ${CYAN}dpkg --list | grep linux-image${RESET}"
    echo
    warn "After installation, reboot to boot into the new kernel."
    warn "At boot, hold Shift (BIOS) or press Esc (UEFI) to access the GRUB menu,"
    warn "then choose 'Advanced options for Ubuntu' to select your kernel."
    echo
}

main "$@"