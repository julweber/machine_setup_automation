#!/usr/bin/env bash
# =============================================================================
# setup_llama_cpp.sh
# Installs llama.cpp on Ubuntu 24.04 with auto or manual GPU backend selection.
# Supports: NVIDIA (CUDA) | AMD (Vulkan) | CPU fallback
#
# Skips installation automatically if llama.cpp binaries are already present
# on the system (PATH, default install dir, or common system paths).
#
# Usage:
#   ./install_llama_cpp.sh              # auto-detect GPU, skip if installed
#   ./install_llama_cpp.sh --nvidia     # force NVIDIA/CUDA
#   ./install_llama_cpp.sh --amd        # force AMD/Vulkan
#   ./install_llama_cpp.sh --cpu        # CPU only
#   ./install_llama_cpp.sh --check      # check installation status and exit
#   ./install_llama_cpp.sh --force      # reinstall even if already present
#   ./install_llama_cpp.sh --help       # show help
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}==> $*${RESET}\n"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
INSTALL_DIR="${HOME}/llama.cpp"
BACKEND=""          # nvidia | amd | cpu  (empty = auto-detect)
INSTALL_SYSTEM=0    # set to 1 to run cmake --install
FORCE=0             # set to 1 to reinstall even if already present
CHECK_ONLY=0        # set to 1 to check status and exit
JOBS=$(nproc)

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  --nvidia          Force NVIDIA CUDA backend
  --amd             Force AMD Vulkan backend
  --cpu             Force CPU-only build (no GPU)
  --dir <path>      Install source to <path>  (default: ~/llama.cpp)
  --system-install  Run 'sudo cmake --install' after build
  --jobs <n>        Parallel build jobs        (default: nproc)
  --force           Reinstall even if llama.cpp is already present
  --check           Check installation status and exit (no install)
  --help            Show this help

${BOLD}Examples:${RESET}
  $0                     # auto-detect, skip if already installed
  $0 --check             # show what's installed and where
  $0 --force --nvidia    # force a fresh CUDA build
  $0 --amd               # Vulkan build
  $0 --cpu --dir /opt/llama.cpp
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nvidia)         BACKEND="nvidia" ;;
    --amd)            BACKEND="amd"    ;;
    --cpu)            BACKEND="cpu"    ;;
    --system-install) INSTALL_SYSTEM=1 ;;
    --force)          FORCE=1          ;;
    --check)          CHECK_ONLY=1     ;;
    --dir)            shift; INSTALL_DIR="$1" ;;
    --jobs)           shift; JOBS="$1"        ;;
    --help|-h)        usage ;;
    *) error "Unknown option: $1  (use --help for usage)" ;;
  esac
  shift
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] && warn "Running as root – not recommended."

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
  warn "This script targets Ubuntu 24.04. Continuing anyway…"
fi

# ── Installation detection ────────────────────────────────────────────────────
# Search locations: PATH, default build dir, common system prefixes
LLAMA_BINARY=""
LLAMA_VERSION=""
LLAMA_FOUND_VIA=""

# Probe locations in priority order
SEARCH_PATHS=(
  "${INSTALL_DIR}/build/bin"
  "${HOME}/.local/bin"
  "/usr/local/bin"
  "/usr/bin"
  "/opt/llama.cpp/build/bin"
)

# Also honour whatever is already on PATH
IFS=':' read -ra _PATH_DIRS <<< "${PATH}"
for _d in "${_PATH_DIRS[@]}"; do
  SEARCH_PATHS+=("${_d}")
done

find_llama_binary() {
  for dir in "${SEARCH_PATHS[@]}"; do
    for bin in llama-cli llama-server llama-bench llama-run; do
      if [[ -x "${dir}/${bin}" ]]; then
        LLAMA_BINARY="${dir}/${bin}"
        LLAMA_FOUND_VIA="${dir}"
        # Try to get version string (best-effort)
        LLAMA_VERSION=$("${LLAMA_BINARY}" --version 2>&1 | head -1 || true)
        return 0
      fi
    done
  done
  return 1
}

print_found_status() {
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║     llama.cpp is already installed ✓         ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Binary found:${RESET}  ${LLAMA_BINARY}"
  echo -e "  ${BOLD}Location:${RESET}      ${LLAMA_FOUND_VIA}"
  [[ -n "$LLAMA_VERSION" ]] && \
  echo -e "  ${BOLD}Version:${RESET}       ${LLAMA_VERSION}"
  echo ""
  # Report all discovered binaries in that dir
  echo -e "  ${BOLD}Binaries in ${LLAMA_FOUND_VIA}:${RESET}"
  for bin in llama-cli llama-server llama-bench llama-run llama-quantize llama-perplexity; do
    if [[ -x "${LLAMA_FOUND_VIA}/${bin}" ]]; then
      echo -e "    ${GREEN}✓${RESET} ${bin}"
    fi
  done
  echo ""
}

banner "Checking for existing llama.cpp installation"

if find_llama_binary; then
  print_found_status

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    info "Run with ${BOLD}--force${RESET} to reinstall, or ${BOLD}--check${RESET} just checks status."
    exit 0
  fi

  if [[ "$FORCE" -eq 0 ]]; then
    echo -e "  ${YELLOW}Nothing to do.${RESET} Use ${BOLD}--force${RESET} to reinstall anyway."
    echo ""
    exit 0
  fi

  warn "--force specified – proceeding with reinstall."
  echo ""
else
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo ""
    echo -e "  ${YELLOW}llama.cpp does not appear to be installed.${RESET}"
    echo -e "  Run the script without ${BOLD}--check${RESET} to install it."
    echo ""
    exit 0
  fi
  success "No existing installation found – proceeding with fresh install."
fi

# ── Auto-detect GPU backend ───────────────────────────────────────────────────
detect_gpu() {
  banner "Auto-detecting GPU"

  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    info "NVIDIA GPU detected via nvidia-smi."
    BACKEND="nvidia"
    return
  fi

  # Check lspci for NVIDIA / AMD
  if command -v lspci &>/dev/null; then
    if lspci 2>/dev/null | grep -qi "NVIDIA"; then
      info "NVIDIA GPU detected via lspci."
      BACKEND="nvidia"
      return
    fi
    if lspci 2>/dev/null | grep -Eqi "AMD|Radeon"; then
      info "AMD GPU detected via lspci."
      BACKEND="amd"
      return
    fi
  fi

  # Check /proc/bus for common GPU identifiers
  if ls /dev/dri/renderD* &>/dev/null; then
    if command -v vulkaninfo &>/dev/null; then
      GPU_INFO=$(vulkaninfo 2>/dev/null || true)
      if echo "$GPU_INFO" | grep -qi "NVIDIA"; then
        info "NVIDIA GPU detected via vulkaninfo."
        BACKEND="nvidia"; return
      fi
      if echo "$GPU_INFO" | grep -Eqi "AMD|Radeon"; then
        info "AMD GPU detected via vulkaninfo."
        BACKEND="amd"; return
      fi
    fi
  fi

  warn "No supported GPU detected – falling back to CPU-only build."
  BACKEND="cpu"
}

[[ -z "$BACKEND" ]] && detect_gpu

echo -e "\n${BOLD}Selected backend:${RESET} ${GREEN}${BACKEND^^}${RESET}\n"

# ── Install base dependencies ─────────────────────────────────────────────────
banner "Installing base dependencies"
sudo apt-get update -qq
sudo apt-get install -y \
  build-essential cmake git curl wget pkg-config \
  libcurl4-openssl-dev ca-certificates
success "Base dependencies installed."

# ── Backend-specific dependencies ────────────────────────────────────────────
install_nvidia_deps() {
  banner "Installing NVIDIA / CUDA dependencies"

  if command -v nvcc &>/dev/null; then
    CUDA_VER=$(nvcc --version | grep -oP 'release \K[0-9.]+')
    success "CUDA toolkit already present (version ${CUDA_VER})."
  else
    info "CUDA toolkit not found – installing via apt…"
    sudo apt-get install -y nvidia-cuda-toolkit
    success "nvidia-cuda-toolkit installed."
  fi

  # Verify driver is loaded
  if ! command -v nvidia-smi &>/dev/null; then
    warn "nvidia-smi not found. Make sure NVIDIA drivers are installed."
    warn "Install with: sudo apt-get install nvidia-driver-XXX"
  else
    nvidia-smi --query-gpu=name,driver_version,memory.total \
               --format=csv,noheader | while IFS=',' read -r name drv mem; do
      info "GPU: ${name} | Driver: ${drv} | VRAM:${mem}"
    done
  fi
}

install_amd_deps() {
  banner "Installing AMD / Vulkan dependencies"
  sudo apt-get install -y \
    libvulkan-dev vulkan-tools glslc \
    mesa-vulkan-drivers libglfw3-dev
  success "Vulkan dependencies installed."

  # Validate Vulkan runtime
  if command -v vulkaninfo &>/dev/null; then
    GPU_NAME=$(vulkaninfo 2>/dev/null | grep -i "deviceName" | head -1 | awk -F'=' '{print $2}' | xargs || echo "unknown")
    info "Vulkan device: ${GPU_NAME}"
  else
    warn "vulkaninfo not available – Vulkan runtime may not be functional."
  fi
}

case "$BACKEND" in
  nvidia) install_nvidia_deps ;;
  amd)    install_amd_deps    ;;
  cpu)    info "CPU-only build – no extra GPU deps needed." ;;
esac

# ── Clone / update repo ───────────────────────────────────────────────────────
banner "Fetching llama.cpp source"
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  info "Existing repo found at ${INSTALL_DIR} – pulling latest…"
  git -C "${INSTALL_DIR}" pull --ff-only
else
  info "Cloning into ${INSTALL_DIR}…"
  git clone https://github.com/ggerganov/llama.cpp "${INSTALL_DIR}"
fi
success "Source ready at ${INSTALL_DIR}."

# ── Configure & build ─────────────────────────────────────────────────────────
banner "Configuring CMake (backend: ${BACKEND^^})"
BUILD_DIR="${INSTALL_DIR}/build"

CMAKE_OPTS=(-DLLAMA_CURL=ON)

case "$BACKEND" in
  nvidia)
    CMAKE_OPTS+=(-DGGML_CUDA=ON)
    info "CUDA acceleration: ON"
    ;;
  amd)
    CMAKE_OPTS+=(-DGGML_VULKAN=ON)
    info "Vulkan acceleration: ON"
    ;;
  cpu)
    info "No GPU acceleration flags set."
    ;;
esac

cmake -S "${INSTALL_DIR}" -B "${BUILD_DIR}" "${CMAKE_OPTS[@]}"
success "CMake configuration complete."

banner "Building llama.cpp (using ${JOBS} parallel jobs)"
cmake --build "${BUILD_DIR}" --config Release -j"${JOBS}"
success "Build complete."

# ── Optional system-wide install ──────────────────────────────────────────────
if [[ "$INSTALL_SYSTEM" -eq 1 ]]; then
  banner "Installing system-wide"
  sudo cmake --install "${BUILD_DIR}"
  success "Installed system-wide."
fi

# ── Shell PATH suggestion ─────────────────────────────────────────────────────
BIN_DIR="${BUILD_DIR}/bin"
SHELL_RC="${HOME}/.bashrc"
[[ "$SHELL" == */zsh ]] && SHELL_RC="${HOME}/.zshrc"

PATH_LINE="export PATH=\"\$PATH:${BIN_DIR}\""

if ! grep -qF "${BIN_DIR}" "${SHELL_RC}" 2>/dev/null; then
  echo ""
  echo "# llama.cpp binaries" >> "${SHELL_RC}"
  echo "${PATH_LINE}" >> "${SHELL_RC}"
  info "Added ${BIN_DIR} to PATH in ${SHELL_RC}."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║        llama.cpp installation complete!      ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Backend:${RESET}    ${GREEN}${BACKEND^^}${RESET}"
echo -e "  ${BOLD}Source:${RESET}     ${INSTALL_DIR}"
echo -e "  ${BOLD}Binaries:${RESET}   ${BIN_DIR}"
echo ""
echo -e "  ${BOLD}Key binaries:${RESET}"
echo -e "    llama-cli     – interactive CLI / single prompt"
echo -e "    llama-server  – OpenAI-compatible HTTP server"
echo -e "    llama-bench   – performance benchmarking"
echo ""
echo -e "  ${BOLD}Quick start:${RESET}"
echo -e "    source ${SHELL_RC}"
echo -e "    llama-cli -m /path/to/model.gguf -p \"Hello!\" -n 128"
echo ""
echo -e "  ${BOLD}Run as a server:${RESET}"
echo -e "    llama-server -m /path/to/model.gguf --host 0.0.0.0 --port 8080"
echo ""
echo -e "  ${BOLD}Tip:${RESET} re-run with ${BOLD}--check${RESET} to verify, ${BOLD}--force${RESET} to reinstall."
echo ""