#!/usr/bin/env bash
# shellcheck disable=SC1091
# =============================================================================
# setup-vllm.sh
# Deploys vLLM as a Docker-based OpenAI-compatible inference server.
# Supports: NVIDIA (CUDA) | AMD (ROCm, amd64 only) | CPU fallback
# Architectures: amd64 (x86_64) | arm64 (aarch64, CUDA and CPU only)
#
# HuggingFace models downloaded via huggingface-cli are automatically
# available inside the container (HF cache dir is mounted).
#
# Usage:
#   ./setup-vllm.sh              # auto-detect GPU, set up vLLM
#   ./setup-vllm.sh --nvidia     # force NVIDIA/CUDA
#   ./setup-vllm.sh --amd        # force AMD/ROCm  (amd64 only)
#   ./setup-vllm.sh --cpu        # CPU only
#   ./setup-vllm.sh --check      # check installation status and exit
#   ./setup-vllm.sh --force      # re-create stack even if already present
#   ./setup-vllm.sh --help       # show help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
PROJECT_DIR="${PROJECT_DIR:-/srv/vllm}"
# HF cache dir on the host — models downloaded via huggingface-cli live here.
# Mounted into the container so vLLM can serve them by HF model ID or path.
HF_CACHE_DIR="${HF_CACHE_DIR:-${HOME}/.cache/huggingface}"

VLLM_PORT="${VLLM_PORT:-8000}"
VLLM_MODEL="${VLLM_MODEL:-}"            # HF model ID or /root/.cache/huggingface path
HF_TOKEN="${HF_TOKEN:-}"               # optional: required for gated models
VLLM_GPU_UTIL="${VLLM_GPU_UTIL:-0.90}"  # GPU memory utilization fraction (GPU backends)
VLLM_EXTRA_ARGS="${VLLM_EXTRA_ARGS:-}"  # additional vLLM server arguments

# ── Multi-GPU / memory tuning ─────────────────────────────────────────────────
VLLM_TENSOR_PARALLEL="${VLLM_TENSOR_PARALLEL:-1}"  # tensor-parallel degree (# GPUs)
VLLM_MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-}"        # cap context length to reduce KV memory
VLLM_DTYPE="${VLLM_DTYPE:-auto}"                    # model dtype: auto|bfloat16|float16|float32
VLLM_SHM_SIZE="${VLLM_SHM_SIZE:-8g}"               # shared memory size (increase for multi-GPU)
VLLM_MAX_NUM_SEQS="${VLLM_MAX_NUM_SEQS:-}"           # max concurrent sequences (default: vLLM default)
VLLM_MAX_NUM_BATCHED_TOKENS="${VLLM_MAX_NUM_BATCHED_TOKENS:-}"  # max batched tokens per iteration (default: vLLM default)

BACKEND=""    # nvidia | amd | cpu  (empty = auto-detect)
FORCE=0
CHECK_ONLY=0

VLLM_TRAEFIK="${VLLM_TRAEFIK:-false}"
VLLM_DOMAIN="${VLLM_DOMAIN:-}"
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"

ARCH=$(uname -m)  # x86_64 | aarch64

# ── Input validation ──────────────────────────────────────────────────────────
# Validate and sanitize user-controlled variables to prevent template injection
# in heredocs. This ensures safe writing to .env and docker-compose.yml files.

validate_model_id() {
  local model="$1"
  # Allow alphanumeric, hyphens, underscores, slashes, colons (for paths/HF IDs)
  if [[ -n "$model" && ! "$model" =~ ^[a-zA-Z0-9_/.:-]+$ ]]; then
    error "VLLM_MODEL contains invalid characters. Allowed: alphanumeric, hyphens, underscores, slashes, colons."
  fi
}

validate_extra_args() {
  local args="$1"
  # Allow only safe characters for command-line arguments
  # Reject backticks, dollar, semicolon, pipe, ampersand, redirection which could break config
  if [[ -n "$args" ]]; then
    local dangerous_pattern='[\`\$;|&<>]'
    if [[ "$args" =~ $dangerous_pattern ]]; then
      error "VLLM_EXTRA_ARGS contains disallowed characters (backtick, \$, \;, \|, \&, \<, \>)."
    fi
  fi
}

validate_domain() {
  local domain="$1"
  # Basic hostname/domain validation
  if [[ -n "$domain" && ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
    error "VLLM_DOMAIN is not a valid domain name."
  fi
}

validate_port() {
  local port="$1"
  if [[ -n "$port" && (! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535) ]]; then
    error "VLLM_PORT must be a number between 1 and 65535."
  fi
}

validate_gpu_util() {
  local util="$1"
  if [[ -n "$util" && (! "$util" =~ ^[0-9]+\.?[0-9]*$ || "$util" == *"."* && "${#util}" -gt 4) ]]; then
    if (($(echo "$util < 0 || $util > 1" | bc -l 2>/dev/null || echo 1))); then
      error "VLLM_GPU_UTIL must be a number between 0.0 and 1.0."
    fi
  fi
}

validate_tensor_parallel() {
  local tp="$1"
  if [[ -n "$tp" && (! "$tp" =~ ^[0-9]+$ || "$tp" -lt 1) ]]; then
    error "VLLM_TENSOR_PARALLEL must be a positive integer."
  fi
}

validate_dtype() {
  local dtype="$1"
  if [[ -z "$dtype" ]]; then return 0; fi
  case "$dtype" in
    auto|bfloat16|float16|float32|float8_e4m3fn|float8_e5m2) ;;
    *) error "VLLM_DTYPE must be one of: auto bfloat16 float16 float32 float8_e4m3fn float8_e5m2" ;;
  esac
}

validate_max_num_seqs() {
  local val="$1"
  if [[ -n "$val" && (! "$val" =~ ^[0-9]+$ || "$val" -lt 1) ]]; then
    error "VLLM_MAX_NUM_SEQS must be a positive integer."
  fi
}

validate_max_num_batched_tokens() {
  local val="$1"
  if [[ -n "$val" && (! "$val" =~ ^[0-9]+$ || "$val" -lt 1) ]]; then
    error "VLLM_MAX_NUM_BATCHED_TOKENS must be a positive integer."
  fi
}

validate_shm_size() {
  local sz="$1"
  if [[ -n "$sz" && ! "$sz" =~ ^[0-9]+[bBkKmMgG]?$ ]]; then
    error "VLLM_SHM_SIZE must be a size string like '8g', '512m', '1024k'."
  fi
}

# Apply validations (only for non-empty values)
validate_model_id "${VLLM_MODEL}"
validate_extra_args "${VLLM_EXTRA_ARGS}"
validate_domain "${VLLM_DOMAIN}"
validate_port "${VLLM_PORT}"
validate_gpu_util "${VLLM_GPU_UTIL}"
validate_tensor_parallel "${VLLM_TENSOR_PARALLEL}"
validate_dtype "${VLLM_DTYPE}"
validate_shm_size "${VLLM_SHM_SIZE}"
validate_max_num_seqs "${VLLM_MAX_NUM_SEQS}"
validate_max_num_batched_tokens "${VLLM_MAX_NUM_BATCHED_TOKENS}"

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}Usage:${RESET} $0 [OPTIONS]"
  echo ""
  echo -e "${BOLD}Options:${RESET}"
  echo "  --nvidia              Force NVIDIA CUDA backend"
  echo "  --amd                 Force AMD ROCm backend  (amd64 only)"
  echo "  --cpu                 Force CPU-only backend"
  echo "  --port <n>            API port  (default: 8000)"
  echo "  --hf-token <token>    HuggingFace token for gated models"
  echo "  --hf-cache <path>     Host HF cache dir  (default: ~/.cache/huggingface)"
  echo "  --gpu-util <frac>     GPU memory utilization 0.0–1.0  (default: 0.90)"
  echo "  --tensor-parallel <n> Number of GPUs for tensor parallelism  (default: 1)"
  echo "  --max-model-len <n>   Max context length – reduce to save KV memory  (default: model max)"
  echo "  --dtype <dtype>       Model dtype: auto|bfloat16|float16|float32  (default: auto)"
  echo "  --shm-size <size>     Shared memory size for the container  (default: 8g)"
  echo "  --max-num-seqs <n>              Max concurrent sequences  (default: vLLM default)"
  echo "  --max-num-batched-tokens <n>    Max batched tokens per iteration  (default: vLLM default)"
  echo "  --dir <path>          Installation directory  (default: /srv/vllm)"
  echo "  --traefik             Enable Traefik reverse-proxy integration"
  echo "  --domain <host>       Domain for Traefik  (required with --traefik)"
  echo "  --force               Re-create stack even if already present"
  echo "  --check               Check installation status and exit"
  echo "  --help                Show this help"
  echo ""
  echo -e "${BOLD}Environment variables${RESET} (all flags above have env-var equivalents):"
  echo "  PROJECT_DIR, HF_CACHE_DIR, VLLM_PORT, HF_TOKEN,"
  echo "  VLLM_GPU_UTIL, VLLM_TENSOR_PARALLEL, VLLM_MAX_MODEL_LEN,"
  echo "  VLLM_DTYPE, VLLM_SHM_SIZE, VLLM_TRAEFIK, VLLM_DOMAIN,"
  echo "  PROXY_NETWORK, VLLM_EXTRA_ARGS,"
  echo "  VLLM_MAX_NUM_SEQS, VLLM_MAX_NUM_BATCHED_TOKENS,"
  echo ""
  echo -e "${BOLD}Model selection${RESET} (set after install, in ${PROJECT_DIR}/.env):"
  echo "  VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct            # HF model ID (auto-downloaded)"
  echo "  VLLM_MODEL=/root/.cache/huggingface/hub/...    # local snapshot path in container"
  echo ""
  echo -e "${BOLD}Examples:${RESET}"
  echo "  $0                                  # auto-detect GPU, set up vLLM"
  echo "  $0 --nvidia --port 8001             # CUDA on port 8001"
  echo "  $0 --amd                            # ROCm  (amd64 only)"
  echo "  $0 --cpu                            # CPU-only"
  echo "  $0 --traefik --domain vllm.example.com"
  echo "  $0 --check                          # show stack status"
  echo "  $0 --force --nvidia                 # re-create CUDA stack"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nvidia)           BACKEND="nvidia" ;;
    --amd)              BACKEND="amd" ;;
    --cpu)              BACKEND="cpu" ;;
    --port)             shift; VLLM_PORT="$1" ;;
    --hf-token)         shift; HF_TOKEN="$1" ;;
    --hf-cache)         shift; HF_CACHE_DIR="$1" ;;
    --gpu-util)         shift; VLLM_GPU_UTIL="$1" ;;
    --tensor-parallel)  shift; VLLM_TENSOR_PARALLEL="$1" ;;
    --max-model-len)    shift; VLLM_MAX_MODEL_LEN="$1" ;;
    --dtype)            shift; VLLM_DTYPE="$1" ;;
    --shm-size)         shift; VLLM_SHM_SIZE="$1" ;;
    --max-num-seqs)         shift; VLLM_MAX_NUM_SEQS="$1" ;;
    --max-num-batched-tokens) shift; VLLM_MAX_NUM_BATCHED_TOKENS="$1" ;;
    --dir)              shift; PROJECT_DIR="$1" ;;
    --traefik)          VLLM_TRAEFIK="true" ;;
    --domain)           shift; VLLM_DOMAIN="$1" ;;
    --force)            FORCE=1 ;;
    --check)            CHECK_ONLY=1 ;;
    --help|-h)          usage ;;
    *) error "Unknown option: $1  (use --help for usage)" ;;
  esac
  shift
done

# ── Guard: ROCm on arm64 is not supported ─────────────────────────────────────
if [[ "$ARCH" == "aarch64" && "$BACKEND" == "amd" ]]; then
  error "ROCm is not supported on arm64 (aarch64). Use --cpu or --nvidia (Grace-Hopper) instead."
fi

# ── Guard: tensor parallelism requires a GPU backend ─────────────────────────
if [[ "${VLLM_TENSOR_PARALLEL}" -gt 1 && "$BACKEND" == "cpu" ]]; then
  error "Tensor parallelism (--tensor-parallel > 1) requires a GPU backend (--nvidia or --amd)."
fi

# ── Detect existing stack ──────────────────────────────────────────────────────
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"

print_found_status() {
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║     vLLM stack is already installed ✓        ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Compose file:${RESET}  ${COMPOSE_FILE}"
  if docker compose -f "${COMPOSE_FILE}" ps --quiet 2>/dev/null | grep -q .; then
    echo -e "  ${BOLD}Status:${RESET}        ${GREEN}running${RESET}"
    docker compose -f "${COMPOSE_FILE}" ps 2>/dev/null | tail -n +2 | \
      while IFS= read -r line; do echo "    ${line}"; done
  else
    echo -e "  ${BOLD}Status:${RESET}        ${YELLOW}stopped${RESET}"
  fi
  echo ""
}

step "Checking for existing vLLM installation"

if [[ -f "$COMPOSE_FILE" ]]; then
  print_found_status

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    info "Run with ${BOLD}--force${RESET} to re-create the stack."
    exit 0
  fi

  if [[ "$FORCE" -eq 0 ]]; then
    echo -e "  ${YELLOW}Nothing to do.${RESET} Use ${BOLD}--force${RESET} to re-create the stack."
    echo ""
    exit 0
  fi

  warn "--force specified – tearing down existing stack."
  (cd "$PROJECT_DIR" && docker compose down 2>/dev/null) || true
  echo ""
else
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo ""
    echo -e "  ${YELLOW}vLLM does not appear to be installed.${RESET}"
    echo -e "  Run the script without ${BOLD}--check${RESET} to install it."
    echo ""
    exit 0
  fi
  success "No existing installation found – proceeding with fresh install."
fi

# ── Pre-flight: sanity ────────────────────────────────────────────────────────
step "Pre-flight checks"

[[ "$(id -u)" -eq 0 ]] && warn "Running as root – not recommended."

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
  warn "This script targets Ubuntu 24.04. Continuing anyway…"
fi

if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Run setup-docker.sh first."
fi
if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi
success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

# CUDA version check (required for Blackwell: CUDA 13.0+)
if [[ "$BACKEND" == "nvidia" ]] || [[ -z "$BACKEND" ]]; then
  if command -v nvcc &>/dev/null; then
    CUDA_VER=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$CUDA_VER" ]]; then
      CUDA_MAJOR=$(echo "$CUDA_VER" | cut -d'.' -f1)
      CUDA_MINOR=$(echo "$CUDA_VER" | cut -d'.' -f2)
      if [[ "$CUDA_MAJOR" -lt 13 || ( "$CUDA_MAJOR" -eq 13 && "$CUDA_MINOR" -lt 0 ) ]]; then
        error "CUDA $CUDA_VER detected — Blackwell requires CUDA 13.0+. Upgrade CUDA or use --cpu."
      fi
      info "CUDA $CUDA_VER detected (meets Blackwell requirement of 13.0+)."
    else
      warn "Could not parse CUDA version from nvcc output."
    fi
  else
    warn "nvcc not found — CUDA toolkit not installed on host (container may still work if driver supports it)."
  fi
fi

# Blackwell INT8 quantization warning
if [[ "$BACKEND" == "nvidia" ]] || [[ -z "$BACKEND" ]]; then
  if nvidia-smi &>/dev/null && nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | grep -qi "12\.1"; then
    if echo "${VLLM_EXTRA_ARGS}" | grep -qi "int8"; then
      error "INT8 quantization is NOT supported on Blackwell (GB10). Use --quantization fp8 or --quantization awq instead."
    fi
  fi
fi

COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "0.0.0")
COMPOSE_MAJOR=$(echo "$COMPOSE_VER" | cut -d'.' -f1)
if [[ "$COMPOSE_MAJOR" -lt 2 ]]; then
  warn "Docker Compose v2+ recommended. Current: ${COMPOSE_VER}"
fi

# Port check (direct mode only)
if [[ "$VLLM_TRAEFIK" != "true" ]]; then
  if ss -tln 2>/dev/null | grep -q ":${VLLM_PORT} "; then
    error "Port ${VLLM_PORT} is already in use. Set a different VLLM_PORT."
  fi
fi

# Traefik pre-flight
if [[ "$VLLM_TRAEFIK" == "true" ]]; then
  ensure_proxy_network
  if [[ -z "$VLLM_DOMAIN" ]]; then
    error "VLLM_DOMAIN must be set when --traefik is used."
  fi
fi

# ── Auto-detect GPU backend ────────────────────────────────────────────────────
detect_gpu() {
  step "Auto-detecting GPU"

  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    info "NVIDIA GPU detected via nvidia-smi."
    BACKEND="nvidia"; return
  fi

  if command -v lspci &>/dev/null; then
    if lspci 2>/dev/null | grep -qi "NVIDIA"; then
      info "NVIDIA GPU detected via lspci."
      BACKEND="nvidia"; return
    fi
    if lspci 2>/dev/null | grep -Eqi "AMD|Radeon"; then
      if [[ "$ARCH" == "aarch64" ]]; then
        warn "AMD GPU detected but ROCm is not supported on arm64. Falling back to CPU."
        BACKEND="cpu"; return
      fi
      info "AMD GPU detected via lspci."
      BACKEND="amd"; return
    fi
  fi

  if ls /dev/dri/renderD* &>/dev/null; then
    if command -v vulkaninfo &>/dev/null; then
      GPU_INFO=$(vulkaninfo 2>/dev/null || true)
      if echo "$GPU_INFO" | grep -qi "NVIDIA"; then
        info "NVIDIA GPU detected via vulkaninfo."
        BACKEND="nvidia"; return
      fi
      if echo "$GPU_INFO" | grep -Eqi "AMD|Radeon"; then
        if [[ "$ARCH" == "aarch64" ]]; then
          warn "AMD GPU detected but ROCm is not supported on arm64. Falling back to CPU."
          BACKEND="cpu"; return
        fi
        info "AMD GPU detected via vulkaninfo."
        BACKEND="amd"; return
      fi
    fi
  fi

  warn "No supported GPU detected – falling back to CPU-only."
  BACKEND="cpu"
}

[[ -z "$BACKEND" ]] && detect_gpu

echo -e "\n${BOLD}Selected backend:${RESET} ${GREEN}${BACKEND^^}${RESET}  |  arch: ${GREEN}${ARCH}${RESET}\n"

# ── ROCm host driver check ─────────────────────────────────────────────────────
if [[ "$BACKEND" == "amd" ]]; then
  step "Checking ROCm host drivers"
  ROCM_OK=1

  if [[ ! -e /dev/kfd ]]; then
    warn "/dev/kfd not found – amdgpu kernel driver may not be loaded."
    ROCM_OK=0
  else
    success "/dev/kfd present."
  fi

  if ! ls /dev/dri/renderD* &>/dev/null; then
    warn "/dev/dri/renderD* not found – GPU render nodes unavailable."
    ROCM_OK=0
  else
    success "/dev/dri/renderD* present."
  fi

  if command -v rocminfo &>/dev/null; then
    if rocminfo 2>/dev/null | grep -qi "Device Type.*GPU"; then
      success "rocminfo reports a GPU device."
    else
      warn "rocminfo found but reports no GPU device."
      ROCM_OK=0
    fi
  else
    warn "rocminfo not found – ROCm may be incomplete."
    warn "Consider running setup-rocm.sh first."
    ROCM_OK=0
  fi

  if [[ "$ROCM_OK" -eq 0 ]]; then
    warn "ROCm host drivers appear incomplete."
    warn "Run setup-rocm.sh to install ROCm, then re-run this script."
    warn "To continue without GPU support, use --cpu instead."
    # Non-fatal: the container may still work if the kernel driver is loaded.
  fi
fi

# ── Resolve Docker image ───────────────────────────────────────────────────────
case "$BACKEND" in
  nvidia)
    # Auto-detect Blackwell (GB10 Grace-Blackwell) via compute capability 12.1
    if nvidia-smi &>/dev/null && nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | grep -qi "12\.1"; then
      VLLM_IMAGE="lharillo/vllm-blackwell-gb10-spark:latest"
      info "Blackwell GPU detected (sm_121) — using lharillo/vllm-blackwell-gb10-spark image."
    else
      VLLM_IMAGE="vllm/vllm-openai:latest"
    fi
    ;;
  amd)    VLLM_IMAGE="vllm/vllm-openai-rocm:latest" ;;  # rocm/vllm deprecated Jan 2026
  cpu)    VLLM_IMAGE="vllm/vllm-openai:latest" ;;
esac
info "Docker image: ${VLLM_IMAGE}"

# ── Prepare directories ────────────────────────────────────────────────────────
step "Creating directories"

if [[ ! -d "$PROJECT_DIR" ]]; then
  sudo mkdir -p "$PROJECT_DIR"
  sudo chown "${USER}:${USER}" "$PROJECT_DIR"
fi
mkdir -p "$HF_CACHE_DIR"
success "Project dir: ${PROJECT_DIR}"
success "HF cache dir: ${HF_CACHE_DIR}"

# ── Write .env ─────────────────────────────────────────────────────────────────
step "Writing .env"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
  warn "Backing up existing .env to ${ENV_FILE}.bak"
  cp "$ENV_FILE" "${ENV_FILE}.bak"
fi

cat > "$ENV_FILE" << EOF
# vLLM configuration
# Edit this file then restart the stack:  cd ${PROJECT_DIR} && docker compose up -d

# ── Model ────────────────────────────────────────────────────────────────────
# HuggingFace model ID (vLLM will fetch/use from the HF cache):
#   VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct
# Path to an HF snapshot inside the container:
#   VLLM_MODEL=/root/.cache/huggingface/hub/models--Qwen--Qwen2.5-7B-Instruct/snapshots/latest
# Path to an LM Studio downloaded model (mounted at /lmstudio-models):
#   VLLM_MODEL=/lmstudio-models/lmstudio-community/Qwen2.5-7B-Instruct-GGUF
VLLM_MODEL=${VLLM_MODEL}

# ── HuggingFace token (leave empty if not needed) ────────────────────────────
HF_TOKEN=${HF_TOKEN}

# ── GPU memory utilization fraction (0.0–1.0) – ignored for CPU backend ──────
VLLM_GPU_UTIL=${VLLM_GPU_UTIL}

# ── Model dtype: auto|bfloat16|float16|float32 ───────────────────────────────
# auto = let vLLM pick (bfloat16 for Ampere+, float16 for older NVIDIA / ROCm)
# Note: For FP8 quantization use VLLM_EXTRA_ARGS="--quantization fp8" instead.
VLLM_DTYPE=${VLLM_DTYPE}

# ── Max context length (tokens) – leave empty to use the model's default ─────
# Reducing this lowers KV-cache memory usage significantly.
# Example: VLLM_MAX_MODEL_LEN=8192
VLLM_MAX_MODEL_LEN=${VLLM_MAX_MODEL_LEN}

# ── Extra vLLM server arguments (space-separated, appended to the command) ───
# Examples:
#   --enable-prefix-caching              (reuse KV cache across requests)
#   --api-key secret123                  (enable API authentication)
#   --quantization fp8                   (FP8 quantisation for memory savings)
#   --kv-cache-dtype fp8                 (FP8 KV cache)
VLLM_EXTRA_ARGS=${VLLM_EXTRA_ARGS}

# ── Max concurrent sequences (default: vLLM default, typically 32-64) ───────
# Higher = more throughput, higher latency. Tune based on request profile.
# Example: VLLM_MAX_NUM_SEQS=256
VLLM_MAX_NUM_SEQS=${VLLM_MAX_NUM_SEQS}

# ── Max batched tokens per iteration (default: vLLM default, typically 256) ─
# Larger = better throughput, smaller = better input latency (ITL).
# Recommended: >8192 for optimal throughput on large GPUs.
# Example: VLLM_MAX_NUM_BATCHED_TOKENS=16384
VLLM_MAX_NUM_BATCHED_TOKENS=${VLLM_MAX_NUM_BATCHED_TOKENS}
EOF

chmod 600 "$ENV_FILE"
success ".env written (mode 600): ${ENV_FILE}"

# ── Generate docker-compose.yml ────────────────────────────────────────────────
step "Generating docker-compose.yml"

# Header + networks
cat > "$COMPOSE_FILE" << EOF
# vLLM Docker Compose
# Generated: $(date -Iseconds)
# Backend: ${BACKEND^^} | Arch: ${ARCH}

networks:
  vllm:
    external: false
EOF

if [[ "$VLLM_TRAEFIK" == "true" ]]; then
  cat >> "$COMPOSE_FILE" << EOF
  ${PROXY_NETWORK}:
    external: true
EOF
fi

# Service header + static environment
cat >> "$COMPOSE_FILE" << EOF

services:
  vllm:
    image: ${VLLM_IMAGE}
    container_name: vllm
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - HF_HOME=/root/.cache/huggingface
      - VLLM_NO_USAGE_STATS=1
EOF

# Blackwell (GB10 Grace-Blackwell) requires specific env vars
# TORCH_CUDA_ARCH_LIST=12.1a — tells PyTorch to compile for sm_121
# VLLM_USE_FLASHINFER_MXFP4_MOE=1 — enables FlashInfer MOE optimization
if [[ "$BACKEND" == "nvidia" ]]; then
  if nvidia-smi &>/dev/null && nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | grep -qi "12\.1"; then
    echo "      - TORCH_CUDA_ARCH_LIST=12.1a" >> "$COMPOSE_FILE"
    echo "      - VLLM_USE_FLASHINFER_MXFP4_MOE=1" >> "$COMPOSE_FILE"
  fi
fi

# arm64 CPU: disable AVX-512 (not available on most arm64 hosts)
if [[ "$BACKEND" == "cpu" && "$ARCH" == "aarch64" ]]; then
  echo "      - VLLM_CPU_DISABLE_AVX512=1" >> "$COMPOSE_FILE"
fi

# Volumes + shared memory
cat >> "$COMPOSE_FILE" << EOF
    volumes:
      - ${HF_CACHE_DIR}:/root/.cache/huggingface
EOF

# Mount LM Studio models dir if it exists on the host
LMSTUDIO_MODELS_DIR="${HOME}/.lmstudio/models"
if [[ -d "$LMSTUDIO_MODELS_DIR" ]]; then
  echo "      - ${LMSTUDIO_MODELS_DIR}:/lmstudio-models" >> "$COMPOSE_FILE"
  info "LM Studio models dir found – mounting ${LMSTUDIO_MODELS_DIR} → /lmstudio-models"
fi

cat >> "$COMPOSE_FILE" << EOF
    shm_size: '${VLLM_SHM_SIZE}'
EOF

# ipc: host is required for tensor-parallel > 1 and recommended for all GPU backends
if [[ "$BACKEND" != "cpu" ]]; then
  echo "    ipc: \"host\"" >> "$COMPOSE_FILE"
fi

# Ports (direct mode)
if [[ "$VLLM_TRAEFIK" != "true" ]]; then
  cat >> "$COMPOSE_FILE" << EOF
    ports:
      - "${VLLM_PORT}:8000"
EOF
fi

# Backend GPU configuration
case "$BACKEND" in
  nvidia)
    cat >> "$COMPOSE_FILE" << 'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
    ;;
  amd)
    cat >> "$COMPOSE_FILE" << 'EOF'
    devices:
      - /dev/kfd
      - /dev/dri
    group_add:
      - video
    cap_add:
      - SYS_PTRACE
    security_opt:
      - seccomp=unconfined
EOF
    ;;
esac

# Traefik labels
if [[ "$VLLM_TRAEFIK" == "true" ]]; then
  cat >> "$COMPOSE_FILE" << EOF
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=${PROXY_NETWORK}"
      - "traefik.http.routers.vllm.rule=Host(\`${VLLM_DOMAIN}\`)"
      - "traefik.http.routers.vllm.entrypoints=websecure"
      - "traefik.http.routers.vllm.tls.certresolver=letsencrypt"
      - "traefik.http.services.vllm.loadbalancer.server.port=8000"
EOF
fi

# Network references
cat >> "$COMPOSE_FILE" << 'EOF'
    networks:
      - vllm
EOF
if [[ "$VLLM_TRAEFIK" == "true" ]]; then
  echo "      - ${PROXY_NETWORK}" >> "$COMPOSE_FILE"
fi

# Command — always present; docker compose substitutes ${VLLM_MODEL} etc. from .env
{
  echo "    command: >"
  echo "      --model \${VLLM_MODEL}"
  echo "      --host 0.0.0.0"
  echo "      --port 8000"
  case "$BACKEND" in
    nvidia|amd) echo "      --gpu-memory-utilization \${VLLM_GPU_UTIL}" ;;
    cpu)        echo "      --device cpu" ;;
  esac
  if [[ "${VLLM_TENSOR_PARALLEL}" -gt 1 ]]; then
    echo "      --tensor-parallel-size ${VLLM_TENSOR_PARALLEL}"
  fi
  # dtype: only emit flag when not 'auto' (vLLM default is auto)
  if [[ "${VLLM_DTYPE}" != "auto" ]]; then
    echo "      --dtype ${VLLM_DTYPE}"
  fi
  # max-model-len: emit flag only when explicitly set
  if [[ -n "${VLLM_MAX_MODEL_LEN}" ]]; then
    echo "      --max-model-len \${VLLM_MAX_MODEL_LEN}"
  fi
  # max-num-seqs: emit flag only when explicitly set
  if [[ -n "${VLLM_MAX_NUM_SEQS}" ]]; then
    echo "      --max-num-seqs \${VLLM_MAX_NUM_SEQS}"
  fi
  # max-num-batched-tokens: emit flag only when explicitly set
  if [[ -n "${VLLM_MAX_NUM_BATCHED_TOKENS}" ]]; then
    echo "      --max-num-batched-tokens \${VLLM_MAX_NUM_BATCHED_TOKENS}"
  fi
  echo "      \${VLLM_EXTRA_ARGS}"
} >> "$COMPOSE_FILE"

success "docker-compose.yml created: ${COMPOSE_FILE}"

# ── Pull image ─────────────────────────────────────────────────────────────────
step "Pulling Docker image: ${VLLM_IMAGE}"
(cd "$PROJECT_DIR" && docker compose pull)
success "Image pulled."

# ── Start stack (only when a model is configured) ─────────────────────────────
if [[ -z "$VLLM_MODEL" ]]; then
  echo ""
  warn "No model configured – skipping container start."
  echo ""
  info "Next steps:"
  info "  1. Download a model with huggingface-cli, e.g.:"
  info "       huggingface-cli download Qwen/Qwen2.5-7B-Instruct"
  info "  2. Set VLLM_MODEL in ${ENV_FILE}:"
  info "       VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct"
  info "  3. Start the stack:"
  info "       cd ${PROJECT_DIR} && docker compose up -d"
  echo ""
else
  step "Starting vLLM stack"
  (cd "$PROJECT_DIR" && docker compose up -d)
  success "Stack started."

  # ── Health check ──────────────────────────────────────────────────────────
  step "Waiting for vLLM to respond"

  if [[ "$VLLM_TRAEFIK" == "true" ]]; then
    info "Traefik mode: skipping direct health check (access via https://${VLLM_DOMAIN})."
  else
    MAX_WAIT=120
    INTERVAL=5
    ELAPSED=0
    READY=false

    while [[ $ELAPSED -lt $MAX_WAIT ]]; do
      if curl -sf "http://localhost:${VLLM_PORT}/health" &>/dev/null; then
        READY=true; break
      fi
      echo -ne "\r    Waited ${ELAPSED}s / ${MAX_WAIT}s …"
      sleep $INTERVAL
      ELAPSED=$((ELAPSED + INTERVAL))
    done
    echo ""

    if [[ "$READY" == "true" ]]; then
      success "vLLM is up and healthy!"
    else
      warn "vLLM did not respond within ${MAX_WAIT}s – it may still be loading the model."
      warn "Follow logs: cd ${PROJECT_DIR} && docker compose logs -f"
    fi
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║        vLLM installation complete!           ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Backend:${RESET}       ${GREEN}${BACKEND^^}${RESET}  (${ARCH})"
echo -e "  ${BOLD}Image:${RESET}         ${VLLM_IMAGE}"
echo -e "  ${BOLD}Project dir:${RESET}   ${PROJECT_DIR}"
echo -e "  ${BOLD}HF cache:${RESET}      ${HF_CACHE_DIR}  →  /root/.cache/huggingface (in container)"
if [[ "${VLLM_TENSOR_PARALLEL}" -gt 1 ]]; then
  echo -e "  ${BOLD}Tensor parallel:${RESET} ${VLLM_TENSOR_PARALLEL} GPUs"
fi
if [[ "${VLLM_DTYPE}" != "auto" ]]; then
  echo -e "  ${BOLD}Dtype:${RESET}         ${VLLM_DTYPE}"
fi
if [[ -n "${VLLM_MAX_MODEL_LEN}" ]]; then
  echo -e "  ${BOLD}Max model len:${RESET} ${VLLM_MAX_MODEL_LEN} tokens"
fi
if [[ -n "${VLLM_MAX_NUM_SEQS}" ]]; then
  echo -e "  ${BOLD}Max num seqs:${RESET}    ${VLLM_MAX_NUM_SEQS}"
fi
if [[ -n "${VLLM_MAX_NUM_BATCHED_TOKENS}" ]]; then
  echo -e "  ${BOLD}Max batched toks:${RESET} ${VLLM_MAX_NUM_BATCHED_TOKENS}"
fi
if [[ -d "${HOME}/.lmstudio/models" ]]; then
  echo -e "  ${BOLD}LM Studio:${RESET}     ${HOME}/.lmstudio/models  →  /lmstudio-models (in container)"
fi
echo -e "  ${BOLD}Config:${RESET}        ${ENV_FILE}"
echo ""
if [[ "$VLLM_TRAEFIK" == "true" ]]; then
  echo -e "  ${BOLD}API (Traefik):${RESET} https://${VLLM_DOMAIN}/v1"
else
  echo -e "  ${BOLD}API:${RESET}           http://localhost:${VLLM_PORT}/v1"
fi

if [[ -n "$VLLM_MODEL" ]]; then
  echo -e "  ${BOLD}Model:${RESET}         ${VLLM_MODEL}"
else
  echo ""
  echo -e "  ${YELLOW}${BOLD}Model not configured yet.${RESET}  Edit ${ENV_FILE} and set VLLM_MODEL,"
  echo -e "  then: cd ${PROJECT_DIR} && docker compose up -d"
fi

echo ""
echo -e "${BOLD}Useful commands:${RESET}"
echo -e "  Start:        cd ${PROJECT_DIR} && docker compose up -d"
echo -e "  Stop:         cd ${PROJECT_DIR} && docker compose down"
echo -e "  Logs:         cd ${PROJECT_DIR} && docker compose logs -f"
echo -e "  Shell:        docker exec -it vllm bash"
echo -e "  Status:       $0 --check"
echo ""
echo -e "  ${BOLD}List loaded models:${RESET}"
echo -e "    curl http://localhost:${VLLM_PORT}/v1/models"
echo ""
echo -e "  ${BOLD}Download a model (on the host):${RESET}"
echo -e "    huggingface-cli download Qwen/Qwen2.5-7B-Instruct"
echo ""
