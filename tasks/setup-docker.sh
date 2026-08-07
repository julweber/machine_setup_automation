#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-docker.sh — Install Docker Engine
# =============================================================================
#
# Description:
#   Installs Docker Engine and related components on Ubuntu/Debian systems.
#
# Environment Variables (optional):
#   DOCKER_APT_KEY_URL    — GPG key URL (default: official Docker repo)
#   DOCKER_KEY_PATH       — Keyring path (default: /etc/apt/keyrings/docker.asc)
#   DOCKER_LIST_PATH      — Sources list path (default: /etc/apt/sources.list.d/docker.list)
#   DOCKER_REPO_URL       — Repo base URL (default: official Docker repo)
#   DOCKER_PACKAGES       — Space-separated package list (default: docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
#   DOCKER_PACKAGES_VERSION — Version pin (e.g. "5:27.5.1-1~ubuntu.24.04~noble")
#   DOCKER_MIRROR          — Custom mirror URL (optional)
#   DOCKER_ENABLE_SERVICE  — Auto-start Docker daemon (default: true)
#
# Options:
#   --force     Skip the Docker installed check and force reinstallation
#   --dry-run   Show what would be done without making changes
#   --help      Show help message
#
# Usage:
#   ./setup-docker.sh
#   DOCKER_PACKAGES_VERSION="5:27.5.1-1~ubuntu.24.04~noble" ./setup-docker.sh
#   ./setup-docker.sh --dry-run
# =============================================================================

set -euo pipefail

# Determine script directory and source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LIB_PATH="$(realpath "${SCRIPT_DIR}/../lib/helpers.sh")"

# shellcheck disable=SC1090
source "${LIB_PATH}" || {
  echo "[ERROR] Shared library not found: ${LIB_PATH}" >&2
  exit 1
}

# Configuration — all overridable via environment variables
: "${DOCKER_APT_KEY_URL:=https://download.docker.com/linux/ubuntu/gpg}"
: "${DOCKER_KEY_PATH:=/etc/apt/keyrings/docker.asc}"
: "${DOCKER_LIST_PATH:=/etc/apt/sources.list.d/docker.list}"
: "${DOCKER_REPO_URL:=https://download.docker.com/linux/ubuntu}"
: "${DOCKER_MIRROR:=}"
: "${DOCKER_ENABLE_SERVICE:=true}"
: "${DOCKER_PACKAGES_VERSION:=}"

# Parse packages — support both space-separated env var and array override
if [[ -n "${DOCKER_PACKAGES:-}" ]]; then
  IFS=' ' read -ra DOCKER_PACKAGES <<< "${DOCKER_PACKAGES}"
else
  declare -a DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
  )
fi

# Parse arguments
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --force              Skip the Docker installed check and force reinstallation"
      echo "  --dry-run            Show what would be done without making changes"
      echo "  --help               Show this help message"
      echo ""
      echo "Environment Variables:"
      echo "  DOCKER_APT_KEY_URL       GPG key URL (default: official Docker repo)"
      echo "  DOCKER_KEY_PATH          Keyring path (default: /etc/apt/keyrings/docker.asc)"
      echo "  DOCKER_LIST_PATH         Sources list path (default: /etc/apt/sources.list.d/docker.list)"
      echo "  DOCKER_REPO_URL          Repo base URL (default: official Docker repo)"
      echo "  DOCKER_MIRROR            Custom mirror URL (optional)"
      echo "  DOCKER_PACKAGES          Space-separated package list"
      echo "  DOCKER_PACKAGES_VERSION  Version pin string"
      echo "  DOCKER_ENABLE_SERVICE    Auto-start Docker daemon (default: true)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# =============================================================================
# Helpers
# =============================================================================

# Run a command, or echo it in dry-run mode
run_cmd() {
  if [[ "${DRY_RUN}" == true ]]; then
    info "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# Check if a package is installed using dpkg-query (more reliable than dpkg -l)
package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Detect Ubuntu/Debian codename from /etc/os-release (works without lsb_release)
detect_codename() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  else
    error "Cannot detect OS — /etc/os-release not found. This script requires Ubuntu or Debian."
  fi
}

# =============================================================================
# Main
# =============================================================================

step "Setting up Docker"

# Detect OS and architecture
step "Detecting system information"
UBUNTU_CODENAME="$(detect_codename)"
ARCH="$(dpkg --print-architecture)"

if [[ -z "${UBUNTU_CODENAME}" ]]; then
  error "Could not detect Ubuntu codename. This script requires Ubuntu 22.04+ or Debian."
fi

info "Detected: Ubuntu ${UBUNTU_CODENAME} on ${ARCH}"

# Check if Docker is already installed
if [[ "${FORCE}" == false ]] && command -v docker &>/dev/null && docker --version &>/dev/null; then
  success "Docker is already installed: $(docker --version 2>/dev/null || echo 'version unknown')"
  # Also check if containerd is available
  if command -v containerd &>/dev/null; then
    info "containerd is also available: $(containerd --version 2>/dev/null || echo 'version unknown')"
  fi
  exit 0
fi

if [[ "${DRY_RUN}" == true ]]; then
  info "Dry-run mode — no changes will be made"
fi

# ---------------------------------------------------------------------------
# Step 1: Update and install prerequisites
# ---------------------------------------------------------------------------
step "Updating package lists and installing prerequisites"
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# ---------------------------------------------------------------------------
# Step 2: Remove conflicting packages
# ---------------------------------------------------------------------------
step "Removing existing Docker/Container packages"
# Note: "docker" (old), "docker.io", "docker-doc", "docker-compose" (v1),
# "docker-compose-v2", "podman-docker", "containerd", "runc" may conflict
declare -a CONFLICTING_PACKAGES=(
  docker
  docker.io
  docker-doc
  docker-compose
  docker-compose-v2
  podman-docker
  runc
)

for pkg in "${CONFLICTING_PACKAGES[@]}"; do
  if package_installed "$pkg"; then
    info "Removing conflicting package: $pkg"
    sudo apt-get remove -y "$pkg"
  else
    info "$pkg not installed — skipping"
  fi
done

# Also remove old containerd.io if present (replaced by containerd package)
if package_installed "containerd.io"; then
  info "Removing old containerd.io package"
  sudo apt-get remove -y containerd.io
fi

# Clean up orphaned dependencies
sudo apt-get autoremove -y --purge 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 3: Add Docker GPG key
# ---------------------------------------------------------------------------
step "Setting up Docker GPG key"
sudo install -m 0755 -d /etc/apt/keyrings

if [[ -f "${DOCKER_KEY_PATH}" ]]; then
  # Verify existing key is valid by checking it contains the expected header
  if head -1 "${DOCKER_KEY_PATH}" | grep -q "BEGIN PGP PUBLIC KEY BLOCK"; then
    info "GPG key already exists and appears valid at ${DOCKER_KEY_PATH}"
  else
    warn "GPG key exists but may be corrupted — re-downloading"
    run_cmd sudo curl -fsSL "${DOCKER_APT_KEY_URL}" -o "${DOCKER_KEY_PATH}"
    run_cmd sudo chmod a+r "${DOCKER_KEY_PATH}"
  fi
else
  run_cmd sudo curl -fsSL "${DOCKER_APT_KEY_URL}" -o "${DOCKER_KEY_PATH}"
  run_cmd sudo chmod a+r "${DOCKER_KEY_PATH}"
  info "GPG key downloaded to ${DOCKER_KEY_PATH}"
fi

# ---------------------------------------------------------------------------
# Step 4: Add Docker repository
# ---------------------------------------------------------------------------
step "Adding Docker repository"

if [[ -n "${DOCKER_MIRROR}" ]]; then
  REPO_LINE="deb [arch=${ARCH} signed-by=${DOCKER_KEY_PATH}] ${DOCKER_MIRROR} ${UBUNTU_CODENAME} stable"
else
  REPO_LINE="deb [arch=${ARCH} signed-by=${DOCKER_KEY_PATH}] ${DOCKER_REPO_URL} ${UBUNTU_CODENAME} stable"
fi

if [[ -f "${DOCKER_LIST_PATH}" ]]; then
  # Check if the existing list matches what we want
  if grep -qF "${DOCKER_REPO_URL}" "${DOCKER_LIST_PATH}" || grep -qF "${DOCKER_MIRROR}" "${DOCKER_LIST_PATH}"; then
    info "Docker repository already configured at ${DOCKER_LIST_PATH}"
  else
    info "Updating existing Docker repository at ${DOCKER_LIST_PATH}"
    run_cmd echo "${REPO_LINE}" | sudo tee "${DOCKER_LIST_PATH}" > /dev/null
  fi
else
  run_cmd echo "${REPO_LINE}" | sudo tee "${DOCKER_LIST_PATH}" > /dev/null
  info "Docker repository added at ${DOCKER_LIST_PATH}"
fi

# shellcheck disable=SC1091
run_cmd sudo apt-get update

# ---------------------------------------------------------------------------
# Step 5: Install Docker Engine
# ---------------------------------------------------------------------------
step "Installing Docker Engine"

# Build the install command with optional version pinning
if [[ -n "${DOCKER_PACKAGES_VERSION}" ]]; then
  info "Installing pinned versions: ${DOCKER_PACKAGES_VERSION}"
  declare -a VERSIONED_PACKAGES=()
  for pkg in "${DOCKER_PACKAGES[@]}"; do
    VERSIONED_PACKAGES+=("${pkg}=${DOCKER_PACKAGES_VERSION}")
  done
  run_cmd sudo apt-get install -y --no-install-recommends "${VERSIONED_PACKAGES[@]}"
else
  run_cmd sudo apt-get install -y --no-install-recommends "${DOCKER_PACKAGES[@]}"
fi

# ---------------------------------------------------------------------------
# Step 6: Configure Docker daemon (optional)
# ---------------------------------------------------------------------------
step "Configuring Docker daemon"
DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"

if [[ -f "${DOCKER_DAEMON_CONFIG}" ]]; then
  info "Existing Docker daemon config found at ${DOCKER_DAEMON_CONFIG} — preserving"
else
  # Create a minimal daemon config for common use cases
  run_cmd sudo mkdir -p /etc/docker
  run_cmd sudo tee "${DOCKER_DAEMON_CONFIG}" > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  info "Created default Docker daemon config at ${DOCKER_DAEMON_CONFIG}"
fi

# ---------------------------------------------------------------------------
# Step 7: Start and enable Docker service
# ---------------------------------------------------------------------------
step "Starting Docker service"
if [[ "${DOCKER_ENABLE_SERVICE}" == true ]]; then
  run_cmd sudo systemctl enable docker
  run_cmd sudo systemctl start docker
  info "Docker service enabled and started"
else
  info "Skipping service start (DOCKER_ENABLE_SERVICE=false)"
fi

# ---------------------------------------------------------------------------
# Step 8: Configure docker group
# ---------------------------------------------------------------------------
step "Configuring docker group"
if getent group docker >/dev/null 2>&1; then
  info "docker group already exists"
else
  run_cmd sudo groupadd docker
  info "Created docker group"
fi

# Fix socket permissions
run_cmd sudo chown root:docker /var/run/docker.sock 2>/dev/null || true

# Add current user to docker group
if id -nG "${USER}" 2>/dev/null | grep -qw docker; then
  info "User '${USER}' is already in the docker group"
else
  run_cmd sudo usermod -aG docker "${USER}"
  info "Added user '${USER}' to docker group"
fi

# ---------------------------------------------------------------------------
# Step 9: Verify installation
# ---------------------------------------------------------------------------
step "Verifying Docker installation"

# Quick verification — faster and more reliable than hello-world
if command -v docker &>/dev/null && docker --version &>/dev/null; then
  success "Docker CLI available: $(docker --version 2>/dev/null || echo 'unknown')"
else
  error "Docker CLI not found after installation"
fi

if command -v containerd &>/dev/null && containerd --version &>/dev/null; then
  info "containerd available: $(containerd --version 2>/dev/null || echo 'unknown')"
else
  warn "containerd not found — Docker may not function correctly"
fi

if command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1; then
  info "Docker Compose available: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo 'unknown')"
else
  warn "Docker Compose not available — install docker-compose-plugin if needed"
fi

if command -v docker-buildx &>/dev/null || docker buildx version &>/dev/null 2>&1; then
  info "Docker Buildx available: $(docker buildx version 2>/dev/null || echo 'unknown')"
else
  warn "Docker Buildx not available — install docker-buildx-plugin if needed"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
success "Docker installed successfully on ${UBUNTU_CODENAME} (${ARCH})"

if [[ "${DRY_RUN}" == true ]]; then
  info "Dry-run complete — no changes were made"
  exit 0
fi

if ! id -nG "${USER}" 2>/dev/null | grep -qw docker; then
  info "Group membership updated. You may need to log out and back in, or run:"
  info "  su - ${USER}  (or:  sg docker -c 'docker info')"
fi
