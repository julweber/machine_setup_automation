#!/usr/bin/env bash
################################################################################
# Neovim Host Installation Script
#
# Description:
#   Installs Neovim directly on the host machine (Ubuntu/Debian) with lazy.nvim
#   plugin manager, LSP support via nvim-lspconfig, and essential productivity
#   plugins. Installed via official PPA for latest stable version.
#
# Architecture:
#   - Installs Neovim from official PPA (latest stable)
#   - Configures in ~/.config/nvim with lazy.nvim
#
# Pre-requisites:
#   - Ubuntu/Debian-based Linux
#   - Root/sudo access for installation
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source helper functions
source "${LIB_DIR}/helpers.sh"

# =============================================================================
# Configuration
# =============================================================================
NEOVIM_VERSION="${NEOVIM_VERSION:-stable}"  # GitHub release tag, e.g. "v0.10.4" or "stable"

# =============================================================================
# Functions
# =============================================================================
# -----------------------------------------------------------------------------
# check_dependencies
#   Validates required tools are available.
# -----------------------------------------------------------------------------
check_dependencies() {
    step "Checking system dependencies"

    if ! command -v curl &>/dev/null; then
        error "curl is required but not found. Install it with: sudo apt-get install -y curl"
    fi
}

# -----------------------------------------------------------------------------
# install_neovim
#   Downloads and installs Neovim from official GitHub releases.
#   Installs to /usr/local/bin for all users.
# -----------------------------------------------------------------------------
install_neovim() {
    step "Installing Neovim ${NEOVIM_VERSION} from GitHub releases"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local archive="${tmp_dir}/nvim-linux-x86_64.tar.gz"

    info "Downloading Neovim ${NEOVIM_VERSION}..."
    curl -fsSL \
        "https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz" \
        -o "$archive"

    info "Extracting to /usr/local..."
    sudo tar -C /usr/local --strip-components=1 -xzf "$archive"

    rm -rf "$tmp_dir"

    # Install python support via pip if available
    if command -v pip3 &>/dev/null; then
        pip3 install --user pynvim 2>/dev/null || true
    fi

    # Verify installation
    if command -v nvim &>/dev/null; then
        success "Neovim installed: $(nvim --version | head -1)"
    else
        error "Installation failed: nvim not found in PATH"
    fi
}

# -----------------------------------------------------------------------------
# create_directories
#   Creates the neovim configuration directory structure.
# -----------------------------------------------------------------------------
create_directories() {
    step "Creating neovim configuration directory"
    
    local config_dir="$HOME/.config/nvim"
    
    mkdir -p "$config_dir/autoload"
    mkdir -p "$config_dir/lua/plugins"
    
    success "Created directory structure in $config_dir"
}

# -----------------------------------------------------------------------------
# generate_neovim_config
#   Copies the neovim configuration template to user's config directory.
#   Idempotent: preserves existing config if present, offers to backup and replace.
# -----------------------------------------------------------------------------
generate_neovim_config() {
    step "Generating neovim configuration"
    
    local config_dir="$HOME/.config/nvim"
    local init_lua="$config_dir/init.lua"
    local template_file="${SCRIPT_DIR}/../templates/neovim/init.lua"
    
    # Check if user already has a custom init.lua
    if [[ -f "$init_lua" ]]; then
        info "Existing neovim configuration found at $init_lua"
        
        # Compare with template to see if it needs update
        if ! diff -q "$template_file" "$init_lua" &>/dev/null; then
            warn "Configuration differs from template. Keeping existing user modification."
            success "Neovim configuration preserved (user customization detected)"
            return 0
        fi
    fi
    
    # Copy template to user's config directory
    cp "$template_file" "$init_lua"
    
    success "Generated neovim configuration from template"
}

# -----------------------------------------------------------------------------
# show_usage_info
#   Displays post-installation usage information.
# -----------------------------------------------------------------------------
show_usage_info() {
    local config_dir="$HOME/.config/nvim"
    echo ""
    echo -e "${BOLD}=== Neovim Setup Complete ===${RESET}"
    echo ""
    echo "Neovim location: $(which nvim)"
    echo "Configuration:   $config_dir/init.lua"
    echo ""
    echo "Quick Start:"
    echo -e "  \\033[1mnvim${RESET}"
    echo ""
    echo "Key Features:"
    echo "  • lazy.nvim - Fast plugin manager with on-demand loading"
    echo "  • nvim-lspconfig - Language Server Protocol support"
    echo "  • telescope.nvim - Fuzzy finder for files, buffers, grep"
    echo "  • nvim-cmp - Intelligent code completion"
    echo "  • treesitter - Advanced syntax highlighting"
    echo "  • gitsigns - Git integration with diff signs"
    echo "  • oil.nvim - Modern file explorer (press '-' to open)"
    echo ""
    echo "Customize your setup by editing: $config_dir/init.lua"
    echo "Add plugins to: $config_dir/lua/plugins/"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    step "Neovim Host Installation Starting..."
    
    check_dependencies
    install_neovim
    create_directories
    generate_neovim_config
    show_usage_info
}

main
