#!/usr/bin/env bash
# =============================================================================
# Agent Docker Runner CLI Setup Script
# =============================================================================
#
# DESCRIPTION:
#   Automated setup script for installing the agent-docker-runner (adr) CLI,
#   a tool that runs coding agents inside isolated Docker containers with 
#   a single command. Supports multiple agents: pi, opencode, claude, codex.
#
# KEY ACTIONS:
#   1. Pre-flight checks: Verifies Docker installation & daemon
#   2. Clones or updates the agent-docker-runner repository to $HOME/tools/agent-docker-runner
#   3. Runs install.sh from the checked out repository
#   4. Builds Docker images for all supported agents (pi, opencode, claude, codex)
#   5. Prints configuration instructions for each agent
#   6. Displays usage information and next steps
#
# IMPORTANT VARIABLES:
#   ADR_REPO_URL    - URL of the git repository to clone (default: official repo)
#   ADR_INSTALL_DIR - Directory to clone the repository to (default: $HOME/tools/agent-docker-runner)
#   ADR_BUILD_AGENTS - Comma-separated list of agents to build images for
#                      (default: pi,opencode,claude,codex)
#
# DEPENDENCIES:
#   - Git: Required to clone/update the repository
#   - Docker: Must be installed and daemon must be running
#   - curl or wget: Used by install.sh for any downloads it may need
#
# OUTPUTS:
#   - ~/.local/bin/adr              - Main CLI executable
#   - ~/.local/share/adr/cli/       - CLI runtime files
#   - ~/.local/share/adr/agents/    - Agent Dockerfiles and entrypoints
#   - ~/.local/share/adr/config-examples/ - Configuration examples
#   - ~/.config/opencode/opencode.json (if configured)
#   - ~/.claude/settings.json (if configured)
#
# USAGE:
#   ./setup-agent-docker-runner.sh
#   
#   # Or with custom agents to build:
#   ADR_BUILD_AGENTS="pi,claude" ./setup-agent-docker-runner.sh
#
# REFERENCE:
#   https://github.com/julweber/agent-docker-runner
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — edit these variables before running
# ─────────────────────────────────────────────────────────────────────────────

ADR_REPO_URL="${ADR_REPO_URL:-https://github.com/julweber/agent-docker-runner.git}"
ADR_INSTALL_DIR="${ADR_INSTALL_DIR:-${HOME}/tools/agent-docker-runner}"  # Where to clone the repo
ADR_BUILD_AGENTS="${ADR_BUILD_AGENTS:-pi,opencode,claude,codex}"  # Comma-separated list of agents to build

# Agent-specific configuration paths (for documentation output)
PI_CONFIG_DIR="${HOME}/.pi"
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
CLAUDE_CONFIG_DIR="${HOME}/.claude"
CODEx_CONFIG_DIR="${HOME}/.codex"

# ─────────────────────────────────────────────────────────────────────────────
# COLOURS & HELPERS
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}▶ $*${RESET}"; }

# Check for git (required for cloning/updating repo)
if ! command -v git &>/dev/null; then
  error "git is not installed or not in PATH."
fi

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

step "Running pre-flight checks"

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH. Run setup-docker.sh first."
fi

if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi

success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

# ─────────────────────────────────────────────────────────────────────────────
# CHECKOUT REPOSITORY AND INSTALL
# ─────────────────────────────────────────────────────────────────────────────

step "Checking out agent-docker-runner repository to ${ADR_INSTALL_DIR}"

if [[ -d "$ADR_INSTALL_DIR/.git" ]]; then
  info "Repository already exists, updating to latest version..."
  cd "$ADR_INSTALL_DIR"
  git fetch origin main
  git checkout main
  git reset --hard origin/main
  success "Repository updated."
else
  info "Cloning repository from ${ADR_REPO_URL}..."
  mkdir -p "$(dirname "$ADR_INSTALL_DIR")"
  git clone "$ADR_REPO_URL" "$ADR_INSTALL_DIR"
  
  # Ensure we're on the main branch
  cd "$ADR_INSTALL_DIR"
  if [[ $(git rev-parse --abbrev-ref HEAD) != "main" ]]; then
    info "Switching to main branch..."
    git checkout main
  fi
  
  success "Repository cloned and checked out."
fi

# Verify install.sh exists in the repository
if [[ ! -f "${ADR_INSTALL_DIR}/install.sh" ]]; then
  error "install.sh not found in ${ADR_INSTALL_DIR}. Repository may be corrupted."
fi

step "Running the installer from ${ADR_INSTALL_DIR}"

cd "$ADR_INSTALL_DIR"
bash install.sh --yes || {
  # If --yes flag doesn't work, run without it (may prompt)
  bash install.sh
}

# Verify installation
if ! command -v adr &>/dev/null; then
  error "adr CLI not found after installation. Check PATH."
fi

success "agent-docker-runner CLI installed successfully from ${ADR_INSTALL_DIR}."

# ─────────────────────────────────────────────────────────────────────────────
# BUILD AGENT IMAGES
# ─────────────────────────────────────────────────────────────────────────────

step "Building Docker images for agents: ${ADR_BUILD_AGENTS}"

IFS=',' read -ra AGENTS <<< "$ADR_BUILD_AGENTS"
for agent in "${AGENTS[@]}"; do
  info "Building image for '${agent}'..."
  adr build "$agent" || warn "Failed to build image for '${agent}'"
done

success "Agent images built."

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION INSTRUCTIONS
# ─────────────────────────────────────────────────────────────────────────────

step "Agent configuration instructions"

echo ""
echo -e "${BOLD}Configure your agents by setting up the following:${RESET}"
echo ""

echo -e "${CYAN}Pi${RESET}:"
echo "  Config directory: ${PI_CONFIG_DIR}/agent/"
if [[ ! -f "${PI_CONFIG_DIR}/agent/settings.json" ]]; then
  echo "  Actions needed:"
  echo "    1. Create directory: mkdir -p ${PI_CONFIG_DIR}/agent"
  echo "    2. Copy example config (if available):"
  ADR_SHARE="${HOME}/.local/share/adr"
  if [[ -d "${ADR_SHARE}/config-examples/pi" ]]; then
    echo "       cp -r ${ADR_SHARE}/config-examples/pi/. ${PI_CONFIG_DIR}/"
  else
    echo "       (Run adr build pi first to get config examples)"
  fi
  echo "    3. Edit ${PI_CONFIG_DIR}/agent/settings.json and add your API keys"
else
  success "${PI_CONFIG_DIR}/agent/settings.json exists"
fi
echo ""

echo -e "${CYAN}Opencode${RESET}:"
if [[ ! -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]]; then
  echo "  Config directory: ${OPENCODE_CONFIG_DIR}"
  echo "  Actions needed:"
  echo "    1. Create directory: mkdir -p ${OPENCODE_CONFIG_DIR}"
  ADR_SHARE="${HOME}/.local/share/adr"
  if [[ -d "${ADR_SHARE}/config-examples/opencode" ]]; then
    echo "    2. Copy example config:"
    echo "       cp ${ADR_SHARE}/config-examples/opencode/opencode.json.example ${OPENCODE_CONFIG_DIR}/opencode.json"
  else
    echo "    2. Create opencode.json manually with your provider configuration"
  fi
  echo "    3. Edit ${OPENCODE_CONFIG_DIR}/opencode.json and add API keys"
else
  success "${OPENCODE_CONFIG_DIR}/opencode.json exists"
fi
echo ""

echo -e "${CYAN}Claude${RESET}:"
if [[ ! -d "$CLAUDE_CONFIG_DIR" ]] || [[ ! -f "${CLAUDE_CONFIG_DIR}/settings.json" ]]; then
  echo "  Config directories: ${CLAUDE_CONFIG_DIR}/ and ${HOME}/.claude.json"
  echo "  Actions needed:"
  echo "    1. Create directory: mkdir -p ${CLAUDE_CONFIG_DIR}"
  ADR_SHARE="${HOME}/.local/share/adr"
  if [[ -d "${ADR_SHARE}/config-examples/claude" ]]; then
    echo "    2. Copy example configs:"
    echo "       cp ${ADR_SHARE}/config-examples/claude/settings.json.example ${CLAUDE_CONFIG_DIR}/settings.json"
    echo "       cp ${ADR_SHARE}/config-examples/claude/.claude.json.example ${HOME}/.claude.json"
  else
    echo "    2. Create settings.json manually with ANTHROPIC_API_KEY in env block"
  fi
  echo "    3. Edit ${CLAUDE_CONFIG_DIR}/settings.json - add your Anthropic API key under \"env\""
  echo "    4. Edit ${HOME}/.claude.json - replace the placeholder with your real API key in approved list"
else
  success "${CLAUDE_CONFIG_DIR}/settings.json exists"
  if [[ -f "${HOME}/.claude.json" ]]; then
    success "${HOME}/.claude.json exists"
  else
    warn "Note: ${HOME}/.claude.json not found (needed to pre-approve API key)"
  fi
fi
echo ""

echo -e "${CYAN}Codex${RESET}:"
if [[ ! -d "$CODEx_CONFIG_DIR" ]]; then
  echo "  Config directory: ${CODEx_CONFIG_DIR}"
  echo "  Actions needed:"
  echo "    1. Create directory: mkdir -p ${CODEx_CONFIG_DIR}"
  ADR_SHARE="${HOME}/.local/share/adr"
  if [[ -d "${ADR_SHARE}/config-examples/codex" ]]; then
    echo "    2. Copy example config (optional):"
    echo "       cp ${ADR_SHARE}/config-examples/codex/config.toml.example ${CODEx_CONFIG_DIR}/config.toml"
  else
    echo "    2. Create config.toml manually if using file-based config"
  fi
  echo "    3. Export API key before running: export OPENAI_API_KEY=your-key-here"
else
  success "${CODEx_CONFIG_DIR} exists"
  info "Export OPENAI_API_KEY environment variable before running codex"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY & NEXT STEPS
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  agent-docker-runner setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

# Check for PATH warning
if ! echo "$PATH" | tr ':' '\n' | grep -q "${HOME}/.local/bin"; then
  warn "Note: ${HOME}/.local/bin is not on your PATH."
  warn "Add this to your shell config file:"
  warn "  export PATH=\"\$PATH:${HOME}/.local/bin\""
  echo ""
fi

# Show installed version
echo -e "${BOLD}Installed version:${RESET}"
adr version
echo ""

echo -e "${BOLD}Configuration status:${RESET}"
if [[ -d "$PI_CONFIG_DIR" && -f "${PI_CONFIG_DIR}/agent/settings.json" ]]; then
  echo -e "  ✓ ${CYAN}Pi${RESET}:        ${PI_CONFIG_DIR}/agent/settings.json (configured)"
else
  echo -e "  ⚠ ${CYAN}Pi${RESET}:        ${PI_CONFIG_DIR}/agent/ (needs configuration)"
fi

if [[ -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]]; then
  echo -e "  ✓ ${CYAN}Opencode${RESET}:   ${OPENCODE_CONFIG_DIR}/opencode.json (configured)"
else
  echo -e "  ⚠ ${CYAN}Opencode${RESET}:   ${OPENCODE_CONFIG_DIR}/ (needs configuration)"
fi

if [[ -d "$CLAUDE_CONFIG_DIR" && -f "${CLAUDE_CONFIG_DIR}/settings.json" ]]; then
  if [[ -f "${HOME}/.claude.json" ]]; then
    echo -e "  ✓ ${CYAN}Claude${RESET}:     ${CLAUDE_CONFIG_DIR}/settings.json + ~/.claude.json (configured)"
  else
    echo -e "  ⚠ ${CYAN}Claude${RESET}:     ${CLAUDE_CONFIG_DIR}/settings.json exists but ~/.claude.json missing"
  fi
else
  echo -e "  ⚠ ${CYAN}Claude${RESET}:     ${CLAUDE_CONFIG_DIR}/ (needs configuration)"
fi

if [[ -d "$CODEx_CONFIG_DIR" ]]; then
  echo -e "  ℹ ${CYAN}Codex${RESET}:      ${CODEx_CONFIG_DIR} exists (set OPENAI_API_KEY env var)"
else
  echo -e "  ⚠ ${CYAN}Codex${RESET}:      ${CODEx_CONFIG_DIR}/ (needs configuration + API key export)"
fi

echo ""

echo -e "${BOLD}Quick start examples:${RESET}"
echo ""
echo -e "  ${BOLD}Interactive session:${RESET}"
echo -e "    cd /path/to/your/project"
echo -e "    adr run pi"
echo ""
echo -e "  ${BOLD}Headless task execution:${RESET}"
echo -e "    adr run -w ~/projects/myapp \\"
echo -e "      --prompt \"Write tests for all untested functions in src/\" pi"
echo ""
echo -e "  ${BOLD}Other agents:${RESET}"
echo -e "    adr build opencode && adr run opencode"
echo -e "    adr build claude && adr run claude"
echo -e "    adr build codex && adr run codex"
echo ""

# Check which images are built
echo -e "${BOLD}Built Docker images:${RESET}"
for agent in "${AGENTS[@]}"; do
  if docker image inspect "coding-agent/${agent}":latest &>/dev/null; then
    echo -e "  ✓ ${CYAN}${agent}${RESET}     (coding-agent/${agent}:latest)"
  else
    echo -e "  ⚠ ${YELLOW}${agent}${RESET}     (image not found, may need manual build)"
  fi
done

echo ""
echo -e "${BOLD}Help commands:${RESET}"
echo -e "  adr --help              Show all commands"
echo -e "  adr run --help          Run options"
echo -e "  adr build --help        Build options"
echo -e "  adr status              Check installed agents"
echo ""
