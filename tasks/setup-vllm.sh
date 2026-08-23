#!/usr/bin/env bash
# shellcheck disable=SC1091
# =============================================================================
# setup-vllm.sh
# Deploys vLLM as a Docker-based OpenAI-compatible inference server.
# Supports: NVIDIA (CUDA) | AMD (ROCm, amd64 only) | CPU fallback
# Architectures: amd64 (x86_64) | arm64 (aarch64, CUDA and CPU only)
#
# Images are pinned release tags by default (override with --image / VLLM_IMAGE).
# DGX Spark (GB10, sm_121) is auto-detected and gets Spark-appropriate
# defaults (lower gpu-memory-utilization, tuning guidance).
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
TEMPLATE_DIR="${SCRIPT_DIR}/../templates/vllm"

# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

# ── Pinned default image tags (verified: amd64 + arm64) ──────────────────────
# Nightly/:latest tags move — deployments should be reproducible. Override
# with --image / VLLM_IMAGE (e.g. nvcr.io/nvidia/vllm, lharillo/..., :gemma).
VLLM_DEFAULT_TAG="v0.27.1"

# ── Defaults ──────────────────────────────────────────────────────────────────
PROJECT_DIR="${PROJECT_DIR:-/srv/vllm}"
# HF cache dir on the host — models downloaded via huggingface-cli live here.
# Mounted into the container so vLLM can serve them by HF model ID or path.
HF_CACHE_DIR="${HF_CACHE_DIR:-${HOME}/.cache/huggingface}"

VLLM_PORT="${VLLM_PORT:-8000}"
VLLM_MODEL="${VLLM_MODEL:-}"            # HF model ID or /root/.cache/huggingface path
HF_TOKEN="${HF_TOKEN:-}"               # optional: required for gated models
VLLM_IMAGE="${VLLM_IMAGE:-}"           # full image override (default: pinned vllm/vllm-openai)
# Empty = resolved after backend detection:
#   0.80 on DGX Spark (sm_121, unified memory), 0.90 other GPU backends
VLLM_GPU_UTIL="${VLLM_GPU_UTIL:-}"
VLLM_EXTRA_ARGS="${VLLM_EXTRA_ARGS:-}"  # additional vLLM server arguments

# ── Multi-GPU / memory tuning ─────────────────────────────────────────────────
VLLM_TENSOR_PARALLEL="${VLLM_TENSOR_PARALLEL:-1}"  # tensor-parallel degree (# GPUs)
VLLM_MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-}"        # cap context length to reduce KV memory
VLLM_DTYPE="${VLLM_DTYPE:-auto}"                    # model dtype: auto|bfloat16|float16|float32
VLLM_SHM_SIZE="${VLLM_SHM_SIZE:-8g}"               # shared memory size (increase for multi-GPU)
VLLM_MAX_NUM_SEQS="${VLLM_MAX_NUM_SEQS:-}"           # max concurrent sequences (default: vLLM default)
VLLM_MAX_NUM_BATCHED_TOKENS="${VLLM_MAX_NUM_BATCHED_TOKENS:-}"  # max batched tokens per iteration (default: vLLM default)

# ── Serving options (flags emitted only when set) ─────────────────────────────
VLLM_SERVED_MODEL_NAME="${VLLM_SERVED_MODEL_NAME:-}"
VLLM_TRUST_REMOTE_CODE="${VLLM_TRUST_REMOTE_CODE:-}"    # true|false
VLLM_LOAD_FORMAT="${VLLM_LOAD_FORMAT:-}"                # e.g. fastsafetensors
VLLM_REASONING_PARSER="${VLLM_REASONING_PARSER:-}"      # e.g. qwen3, nemotron_v3
VLLM_TOOL_CALL_PARSER="${VLLM_TOOL_CALL_PARSER:-}"      # e.g. qwen3, qwen3_xml
VLLM_ENABLE_AUTO_TOOL_CHOICE="${VLLM_ENABLE_AUTO_TOOL_CHOICE:-}"  # true|false

# ── Spark / startup options ───────────────────────────────────────────────────
# Opt-in KEY=VALUE env vars for GB10 (sm_121), space-separated.
# Version-specific workarounds for specific image tags, e.g.:
#   VLLM_SPARK_EXTRA_ENV="TORCH_CUDA_ARCH_LIST=12.1a VLLM_USE_FLASHINFER_MXFP4_MOE=1"
VLLM_SPARK_EXTRA_ENV="${VLLM_SPARK_EXTRA_ENV:-}"
VLLM_HEALTH_TIMEOUT="${VLLM_HEALTH_TIMEOUT:-}"  # empty = 900s (GPU) / 120s (CPU)
WARMUP=1                                          # post-health warmup request (--no-warmup to skip)

BACKEND=""    # nvidia | amd | cpu  (empty = auto-detect)
FORCE=0
CHECK_ONLY=0

VLLM_TRAEFIK="${VLLM_TRAEFIK:-false}"
VLLM_DOMAIN="${VLLM_DOMAIN:-}"
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"

ARCH=$(uname -m)  # x86_64 | aarch64

# ── Input validation ──────────────────────────────────────────────────────────
# Validate and sanitize user-controlled variables to prevent template injection
# in envsubst templates. This ensures safe writing to .env and compose files.

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

validate_image() {
  local img="$1"
  if [[ -n "$img" && ! "$img" =~ ^[a-zA-Z0-9_./:@-]+$ ]]; then
    error "VLLM_IMAGE contains invalid characters. Expected a Docker image reference like repo/org/image:tag."
  fi
  if [[ -n "$img" ]] && { [[ "$img" == *:latest ]] || [[ "$img" != *:* && "$img" != *@* ]]; }; then
    warn "VLLM_IMAGE '${img}' uses a moving tag — deployments with :latest/digest-less tags are not reproducible. Pin a release tag or digest."
  fi
}

validate_bool_opt() {
  local name="$1" val="$2"
  if [[ -n "$val" && ! ( "$val" == "true" || "$val" == "false" ) ]]; then
    error "${name} must be true or false (got: ${val})."
  fi
}

# Identifier-like free values: parser names, served model names, load formats
validate_ident_opt() {
  local name="$1" val="$2"
  if [[ -n "$val" && ! "$val" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
    error "${name} contains invalid characters. Allowed: alphanumeric, dot, underscore, slash, hyphen."
  fi
}

validate_spark_extra_env() {
  local kv
  if [[ -z "$1" ]]; then return 0; fi
  for kv in $1; do
    if [[ ! "$kv" =~ ^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_./:@+-]+$ ]]; then
      error "VLLM_SPARK_EXTRA_ENV entry '${kv}' is not a valid KEY=VALUE pair (no spaces, no shell characters)."
    fi
  done
}

# Apply validations (only for non-empty values)
validate_model_id "${VLLM_MODEL}"
validate_extra_args "${VLLM_EXTRA_ARGS}"
validate_domain "${VLLM_DOMAIN}"
validate_port "${VLLM_PORT}"
validate_gpu_util "${VLLM_GPU_UTIL}"
validate_image "${VLLM_IMAGE}"
validate_tensor_parallel "${VLLM_TENSOR_PARALLEL}"
validate_dtype "${VLLM_DTYPE}"
validate_shm_size "${VLLM_SHM_SIZE}"
validate_max_num_seqs "${VLLM_MAX_NUM_SEQS}"
validate_max_num_batched_tokens "${VLLM_MAX_NUM_BATCHED_TOKENS}"
validate_ident_opt "VLLM_SERVED_MODEL_NAME" "${VLLM_SERVED_MODEL_NAME}"
validate_bool_opt "VLLM_TRUST_REMOTE_CODE" "${VLLM_TRUST_REMOTE_CODE}"
validate_ident_opt "VLLM_LOAD_FORMAT" "${VLLM_LOAD_FORMAT}"
validate_ident_opt "VLLM_REASONING_PARSER" "${VLLM_REASONING_PARSER}"
validate_ident_opt "VLLM_TOOL_CALL_PARSER" "${VLLM_TOOL_CALL_PARSER}"
validate_bool_opt "VLLM_ENABLE_AUTO_TOOL_CHOICE" "${VLLM_ENABLE_AUTO_TOOL_CHOICE}"
validate_spark_extra_env "${VLLM_SPARK_EXTRA_ENV}"
if [[ -n "${VLLM_HEALTH_TIMEOUT}" && (! "${VLLM_HEALTH_TIMEOUT}" =~ ^[0-9]+$ || "${VLLM_HEALTH_TIMEOUT}" -lt 1) ]]; then
  error "VLLM_HEALTH_TIMEOUT must be a positive integer (seconds)."
fi

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
  echo "  --image <image:tag>   Docker image override (default: pinned vllm/vllm-openai)"
  echo "  --gpu-util <frac>     GPU memory utilization 0.0–1.0"
  echo "                        (default: 0.80 on DGX Spark, 0.90 other NVIDIA/AMD GPUs)"
  echo "  --tensor-parallel <n> Number of GPUs for tensor parallelism  (default: 1)"
  echo "  --max-model-len <n>   Max context length – reduce to save KV memory  (default: model max)"
  echo "  --dtype <dtype>       Model dtype: auto|bfloat16|float16|float32  (default: auto)"
  echo "  --shm-size <size>     Shared memory size for the container  (default: 8g)"
  echo "  --max-num-seqs <n>    Max concurrent sequences  (default: vLLM default)"
  echo "  --max-num-batched-tokens <n>  Max batched tokens per iteration  (default: vLLM default)"
  echo "  --served-model-name <name>  Client-facing model ID"
  echo "  --trust-remote-code   Trust remote code in the model repo"
  echo "  --load-format <fmt>   Weight load format (e.g. fastsafetensors)"
  echo "  --reasoning-parser <name>  Reasoning parser for agent-ready serving"
  echo "  --tool-call-parser <name>  Tool-call parser for agent-ready serving"
  echo "  --enable-auto-tool-choice  Enable automatic tool choice"
  echo "  --spark-env <KEY=V ...>    Extra env vars for DGX Spark (version-specific workarounds)"
  echo "  --health-timeout <s>  Seconds to wait for /health  (default: 900 GPU / 120 CPU)"
  echo "  --no-warmup           Skip the post-health warmup request"
  echo "  --dir <path>          Installation directory  (default: /srv/vllm)"
  echo "  --traefik             Enable Traefik reverse-proxy integration"
  echo "  --domain <host>       Domain for Traefik  (required with --traefik)"
  echo "  --force               Re-create stack even if already present"
  echo "  --check               Check installation status and exit"
  echo "  --help                Show this help"
  echo ""
  echo -e "${BOLD}Environment variables${RESET} (all flags above have env-var equivalents):"
  echo "  PROJECT_DIR, HF_CACHE_DIR, VLLM_PORT, HF_TOKEN, VLLM_IMAGE,"
  echo "  VLLM_GPU_UTIL, VLLM_TENSOR_PARALLEL, VLLM_MAX_MODEL_LEN,"
  echo "  VLLM_DTYPE, VLLM_SHM_SIZE, VLLM_TRAEFIK, VLLM_DOMAIN,"
  echo "  PROXY_NETWORK, VLLM_EXTRA_ARGS,"
  echo "  VLLM_MAX_NUM_SEQS, VLLM_MAX_NUM_BATCHED_TOKENS,"
  echo "  VLLM_SERVED_MODEL_NAME, VLLM_TRUST_REMOTE_CODE, VLLM_LOAD_FORMAT,"
  echo "  VLLM_REASONING_PARSER, VLLM_TOOL_CALL_PARSER,"
  echo "  VLLM_ENABLE_AUTO_TOOL_CHOICE, VLLM_SPARK_EXTRA_ENV, VLLM_HEALTH_TIMEOUT,"
  echo ""
  echo -e "${BOLD}Model selection${RESET} (set after install, in ${PROJECT_DIR}/.env):"
  echo "  VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct            # HF model ID (auto-downloaded)"
  echo "  VLLM_MODEL=/root/.cache/huggingface/hub/...    # local snapshot path in container"
  echo ""
  echo -e "${BOLD}Model fit (DGX Spark, 128 GB unified memory):${RESET}"
  echo "  100–130B MoE NVFP4 (~10–15B active) is the best Spark fit;"
  echo "  up to ~200B NVFP4 fits the 128 GB pool. Dense models are poorly"
  echo "  matched. See the NVIDIA DGX Spark vLLM model support matrix:"
  echo "  https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/vllm/README.md"
  echo ""
  echo -e "${BOLD}Examples:${RESET}"
  echo "  $0                                  # auto-detect GPU, set up vLLM"
  echo "  $0 --nvidia --port 8001             # CUDA on port 8001"
  echo "  $0 --amd                            # ROCm  (amd64 only)"
  echo "  $0 --cpu                            # CPU-only"
  echo "  $0 --traefik --domain vllm.example.com"
  echo "  $0 --image nvcr.io/nvidia/vllm:26.05-py3   # NGC image (needs: docker login nvcr.io)"
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
    --image)            shift; VLLM_IMAGE="$1" ;;
    --gpu-util)         shift; VLLM_GPU_UTIL="$1" ;;
    --tensor-parallel)  shift; VLLM_TENSOR_PARALLEL="$1" ;;
    --max-model-len)    shift; VLLM_MAX_MODEL_LEN="$1" ;;
    --dtype)            shift; VLLM_DTYPE="$1" ;;
    --shm-size)         shift; VLLM_SHM_SIZE="$1" ;;
    --max-num-seqs)         shift; VLLM_MAX_NUM_SEQS="$1" ;;
    --max-num-batched-tokens) shift; VLLM_MAX_NUM_BATCHED_TOKENS="$1" ;;
    --served-model-name) shift; VLLM_SERVED_MODEL_NAME="$1" ;;
    --trust-remote-code) VLLM_TRUST_REMOTE_CODE="true" ;;
    --load-format)      shift; VLLM_LOAD_FORMAT="$1" ;;
    --reasoning-parser) shift; VLLM_REASONING_PARSER="$1" ;;
    --tool-call-parser) shift; VLLM_TOOL_CALL_PARSER="$1" ;;
    --enable-auto-tool-choice) VLLM_ENABLE_AUTO_TOOL_CHOICE="true" ;;
    --spark-env)        shift; VLLM_SPARK_EXTRA_ENV="$1" ;;
    --health-timeout)   shift; VLLM_HEALTH_TIMEOUT="$1" ;;
    --no-warmup)        WARMUP=0 ;;
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
  warn "This script targets Ubuntu. Continuing anyway…"
fi

if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Run setup-docker.sh first."
fi
if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi
success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

if ! command -v envsubst &>/dev/null; then
  error "envsubst is not installed. Required for template rendering. Install with: sudo apt-get install gettext-base"
fi

# NVIDIA pre-flight: driver + container toolkit (for Docker deployments the
# host CUDA *toolkit* is irrelevant — the image ships CUDA, the driver matters).
if [[ "$BACKEND" == "nvidia" ]] || [[ -z "$BACKEND" ]]; then
  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)
    if [[ -n "$DRIVER_VER" ]]; then
      DRIVER_MAJOR="${DRIVER_VER%%.*}"
      if [[ "$DRIVER_MAJOR" =~ ^[0-9]+$ && "$DRIVER_MAJOR" -lt 580 ]]; then
        if nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | grep -qi "12\.1"; then
          error "GPU driver $DRIVER_VER is too old for DGX Spark (GB10) — a CUDA 13-era driver (>= 580) is required."
        fi
        warn "GPU driver $DRIVER_VER is old; the pinned vLLM image (CUDA 13) needs driver >= 580. Update the driver or override the image with --image."
      else
        info "GPU driver ${DRIVER_VER} detected (CUDA 13 compatible: >= 580)."
      fi
    fi
    # NVIDIA Container Toolkit must be available to the daemon for --gpus
    if ! docker info --format '{{.Runtimes}}' 2>/dev/null | grep -qi nvidia; then
      warn "No 'nvidia' runtime in docker info — NVIDIA Container Toolkit may not be installed."
      warn "The vLLM image needs GPU passthrough: install it via setup-docker.sh or the NVIDIA docs."
    fi
    # Host CUDA toolkit — informational only (the container image ships CUDA)
    if command -v nvcc &>/dev/null; then
      CUDA_VER=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+\.[0-9]+' | head -1 || true)
      [[ -n "$CUDA_VER" ]] && info "Host CUDA toolkit: $CUDA_VER (informational — the image ships its own CUDA)."
    else
      info "No host CUDA toolkit (nvcc) — fine for Docker deployments."
    fi
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

# ── DGX Spark (GB10) detection: compute capability 12.1 (sm_121) ─────────────
# Note: nvidia-smi reports N/A for memory fields on Spark (UMA) — never use
# memory-based logic here; compute capability is the reliable signal.
is_spark() {
  nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | grep -qi "12\.1"
}

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
    if is_spark; then
      info "DGX Spark (GB10, sm_121) detected — using Spark-appropriate defaults."
    fi
    if [[ -z "$VLLM_IMAGE" ]]; then
      VLLM_IMAGE="vllm/vllm-openai:${VLLM_DEFAULT_TAG}"
      info "Default image pinned: ${VLLM_IMAGE} (override with --image)"
    fi
    ;;
  amd)    [[ -z "$VLLM_IMAGE" ]] && VLLM_IMAGE="vllm/vllm-openai-rocm:${VLLM_DEFAULT_TAG}" ;;
  cpu)    [[ -z "$VLLM_IMAGE" ]] && VLLM_IMAGE="vllm/vllm-openai:${VLLM_DEFAULT_TAG}" ;;
esac
info "Docker image: ${VLLM_IMAGE}"

# ── Resolve defaults that depend on the backend ───────────────────────────────
if [[ -z "$VLLM_GPU_UTIL" && "$BACKEND" != "cpu" ]]; then
  if [[ "$BACKEND" == "nvidia" ]] && is_spark; then
    VLLM_GPU_UTIL="0.80"
  else
    VLLM_GPU_UTIL="0.90"
  fi
  info "VLLM_GPU_UTIL not set — defaulting to ${VLLM_GPU_UTIL}."
fi

if [[ -z "$VLLM_HEALTH_TIMEOUT" ]]; then
  if [[ "$BACKEND" == "cpu" ]]; then
    VLLM_HEALTH_TIMEOUT=120
  else
    VLLM_HEALTH_TIMEOUT=900
  fi
fi
validate_gpu_util "${VLLM_GPU_UTIL}"

if [[ "${VLLM_TENSOR_PARALLEL}" -gt 1 && "$BACKEND" == "nvidia" ]]; then
  GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1 || true)
  if [[ "$GPU_COUNT" == "1" ]]; then
    warn "VLLM_TENSOR_PARALLEL=${VLLM_TENSOR_PARALLEL} but only 1 GPU is visible."
    warn "Tensor parallelism across multiple DGX Sparks needs the Ray cluster path"
    warn "(see https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/vllm/README.md)."
  fi
fi

# ── Prepare directories ────────────────────────────────────────────────────────
step "Creating directories"

if [[ ! -d "$PROJECT_DIR" ]]; then
  sudo mkdir -p "$PROJECT_DIR"
  sudo chown "${USER}:${USER}" "$PROJECT_DIR"
fi
mkdir -p "$HF_CACHE_DIR"
# vLLM compile cache (torch.compile/Inductor/Triton) — survives container restarts
VLLM_CACHE_DIR="${PROJECT_DIR}/.vllm-cache"
mkdir -p "$VLLM_CACHE_DIR"
# LM Studio models dir (mounted at /lmstudio-models); created if absent so the
# bind mount in the compose template is always valid.
LMSTUDIO_MODELS_DIR="${HOME}/.lmstudio/models"
mkdir -p "$LMSTUDIO_MODELS_DIR"
success "Project dir: ${PROJECT_DIR}"
success "HF cache dir: ${HF_CACHE_DIR}"
success "vLLM cache dir: ${VLLM_CACHE_DIR}"

# ── Spark-conditional guidance (for .env comments) ────────────────────────────
if [[ "$BACKEND" == "nvidia" ]] && is_spark; then
  VLLM_GPU_UTIL_NOTE='# On DGX Spark this fraction applies to the 128 GB *unified* pool shared'
  VLLM_GPU_UTIL_NOTE="${VLLM_GPU_UTIL_NOTE}"$'\n'"# with the OS, page cache and the container runtime — leave headroom."
  VLLM_GPU_UTIL_NOTE="${VLLM_GPU_UTIL_NOTE}"$'\n'"# If the box shows memory pressure:  sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'"
  VLLM_CONCURRENCY_NOTE='# DGX Spark is bandwidth-bound, not a large GPU:'
  VLLM_CONCURRENCY_NOTE="${VLLM_CONCURRENCY_NOTE}"$'\n'"#   max-num-seqs 4–8 is the right scale — above ~4 concurrent decode streams"
  VLLM_CONCURRENCY_NOTE="${VLLM_CONCURRENCY_NOTE}"$'\n'"#   the bandwidth tax outweighs batching and TTFT spikes. (datacenter: 128–256)"
  VLLM_CONCURRENCY_NOTE="${VLLM_CONCURRENCY_NOTE}"$'\n'"#   max-num-batched-tokens: 8192 is the NVIDIA Spark recipe value."
else
  VLLM_GPU_UTIL_NOTE='# Fraction of GPU memory vLLM may use. Higher = more KV cache, less headroom.'
  VLLM_CONCURRENCY_NOTE='# Higher max-num-seqs = more throughput, higher latency.'
  VLLM_CONCURRENCY_NOTE="${VLLM_CONCURRENCY_NOTE}"$'\n'"# Example: VLLM_MAX_NUM_SEQS=256  (tune to your request profile)"
  VLLM_CONCURRENCY_NOTE="${VLLM_CONCURRENCY_NOTE}"$'\n'"# max-num-batched-tokens: >8192 for optimal throughput on large GPUs,"
  VLLM_CONCURRENCY_NOTE="${VLLM_CONCURRENCY_NOTE}"$'\n'"# smaller = better input latency (ITL)."
fi

# ── Write .env (rendered from templates/vllm/env.template) ───────────────────
step "Writing .env"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
  warn "Backing up existing .env to ${ENV_FILE}.bak"
  cp "$ENV_FILE" "${ENV_FILE}.bak"
fi

GENERATED_DATE="$(date -Iseconds)"
export PROJECT_DIR VLLM_MODEL HF_TOKEN VLLM_GPU_UTIL VLLM_DTYPE VLLM_MAX_MODEL_LEN \
  VLLM_SERVED_MODEL_NAME VLLM_TRUST_REMOTE_CODE VLLM_LOAD_FORMAT \
  VLLM_REASONING_PARSER VLLM_TOOL_CALL_PARSER VLLM_ENABLE_AUTO_TOOL_CHOICE \
  VLLM_EXTRA_ARGS VLLM_MAX_NUM_SEQS VLLM_MAX_NUM_BATCHED_TOKENS \
  VLLM_GPU_UTIL_NOTE VLLM_CONCURRENCY_NOTE
# shellcheck disable=SC2016  # envsubst expects the literal variable list
envsubst '${PROJECT_DIR} ${VLLM_MODEL} ${HF_TOKEN} ${VLLM_GPU_UTIL} ${VLLM_DTYPE} ${VLLM_MAX_MODEL_LEN} ${VLLM_SERVED_MODEL_NAME} ${VLLM_TRUST_REMOTE_CODE} ${VLLM_LOAD_FORMAT} ${VLLM_REASONING_PARSER} ${VLLM_TOOL_CALL_PARSER} ${VLLM_ENABLE_AUTO_TOOL_CHOICE} ${VLLM_EXTRA_ARGS} ${VLLM_MAX_NUM_SEQS} ${VLLM_MAX_NUM_BATCHED_TOKENS} ${VLLM_GPU_UTIL_NOTE} ${VLLM_CONCURRENCY_NOTE}' \
  < "${TEMPLATE_DIR}/env.template" > "$ENV_FILE"
chmod 600 "$ENV_FILE"
success ".env written (mode 600): ${ENV_FILE}"

# ── Write extra-vars.env (backend-specific env vars, kept out of .env) ───────
EXTRA_VARS_FILE="${PROJECT_DIR}/extra-vars.env"
{
  echo "# Generated by setup-vllm.sh — re-rendered on --force, safe to delete."
  if [[ "$BACKEND" == "cpu" && "$ARCH" == "aarch64" ]]; then
    echo "# AVX-512 is not available on most arm64 hosts"
    echo "VLLM_CPU_DISABLE_AVX512=1"
  fi
  if [[ "$BACKEND" == "nvidia" && -n "$VLLM_SPARK_EXTRA_ENV" ]]; then
    echo "# DGX Spark (sm_121) env vars — version-specific workarounds for the image tag"
    for _kv in $VLLM_SPARK_EXTRA_ENV; do
      echo "$_kv"
    done
  fi
} > "$EXTRA_VARS_FILE"
chmod 600 "$EXTRA_VARS_FILE"
success "extra-vars.env written: ${EXTRA_VARS_FILE}"

# ── Build optional server flags (one flag group per line; the template's
#    folded-scalar command block joins them with spaces. Continuation lines
#    carry the 6-space block-scalar indent. Empty flags collapse safely.) ─────
VLLM_COMMAND_FLAGS=""
_add_flag() { VLLM_COMMAND_FLAGS="${VLLM_COMMAND_FLAGS:+${VLLM_COMMAND_FLAGS}$'\n'      }$1"; }

# tensor-parallel: emit flag only when > 1 (vLLM default is 1)
if [[ "${VLLM_TENSOR_PARALLEL}" -gt 1 ]]; then
  _add_flag "--tensor-parallel-size ${VLLM_TENSOR_PARALLEL}"
fi
# dtype: emit flag only when not 'auto' (vLLM default is auto)
if [[ "${VLLM_DTYPE}" != "auto" ]]; then
  _add_flag "--dtype ${VLLM_DTYPE}"
fi
# Values from .env stay compose-time substitutions (\$ kept literal)
if [[ -n "${VLLM_MAX_MODEL_LEN}" ]]; then
  _add_flag "--max-model-len \${VLLM_MAX_MODEL_LEN}"
fi
if [[ -n "${VLLM_MAX_NUM_SEQS}" ]]; then
  _add_flag "--max-num-seqs \${VLLM_MAX_NUM_SEQS}"
fi
if [[ -n "${VLLM_MAX_NUM_BATCHED_TOKENS}" ]]; then
  _add_flag "--max-num-batched-tokens \${VLLM_MAX_NUM_BATCHED_TOKENS}"
fi
if [[ -n "${VLLM_SERVED_MODEL_NAME}" ]]; then
  _add_flag "--served-model-name ${VLLM_SERVED_MODEL_NAME}"
fi
if [[ "${VLLM_TRUST_REMOTE_CODE}" == "true" ]]; then
  _add_flag "--trust-remote-code"
fi
if [[ -n "${VLLM_LOAD_FORMAT}" ]]; then
  _add_flag "--load-format ${VLLM_LOAD_FORMAT}"
fi
if [[ -n "${VLLM_REASONING_PARSER}" ]]; then
  _add_flag "--reasoning-parser ${VLLM_REASONING_PARSER}"
fi
if [[ -n "${VLLM_TOOL_CALL_PARSER}" ]]; then
  _add_flag "--tool-call-parser ${VLLM_TOOL_CALL_PARSER}"
fi
if [[ "${VLLM_ENABLE_AUTO_TOOL_CHOICE}" == "true" ]]; then
  _add_flag "--enable-auto-tool-choice"
fi

# ── Render docker-compose.yml (from templates/vllm/docker-compose.<backend>.<mode>.yml) ──
step "Generating docker-compose.yml"

EXPOSURE_MODE="direct"
[[ "$VLLM_TRAEFIK" == "true" ]] && EXPOSURE_MODE="traefik"
COMPOSE_TEMPLATE="${TEMPLATE_DIR}/docker-compose.${BACKEND}.${EXPOSURE_MODE}.yml"

export VLLM_IMAGE VLLM_SHM_SIZE HF_CACHE_DIR PROJECT_DIR LMSTUDIO_MODELS_DIR \
  VLLM_PORT PROXY_NETWORK VLLM_DOMAIN VLLM_COMMAND_FLAGS GENERATED_DATE
# shellcheck disable=SC2016  # envsubst expects the literal variable list
# Note: VLLM_MODEL / VLLM_GPU_UTIL / VLLM_EXTRA_ARGS are deliberately NOT in
# the list — the compose file keeps them for runtime substitution from .env.
envsubst '${VLLM_IMAGE} ${VLLM_SHM_SIZE} ${HF_CACHE_DIR} ${PROJECT_DIR} ${LMSTUDIO_MODELS_DIR} ${VLLM_PORT} ${PROXY_NETWORK} ${VLLM_DOMAIN} ${VLLM_COMMAND_FLAGS} ${GENERATED_DATE}' \
  < "$COMPOSE_TEMPLATE" > "$COMPOSE_FILE"
# An empty VLLM_COMMAND_FLAGS leaves a whitespace-only line — strip for clean YAML
sed -i 's/[[:space:]]*$//' "$COMPOSE_FILE"
success "docker-compose.yml created: ${COMPOSE_FILE} (backend: ${BACKEND}, exposure: ${EXPOSURE_MODE})"

# ── Pull image ─────────────────────────────────────────────────────────────────
step "Pulling Docker image: ${VLLM_IMAGE}"
(cd "$PROJECT_DIR" && docker compose pull) || {
  # Surface the common case: nvcr.io images need NGC authentication
  if [[ "$VLLM_IMAGE" == nvcr.io/* ]]; then
    error "docker compose pull failed for NGC image ${VLLM_IMAGE}."
    error "NGC images require authentication: create a free API key at https://api.ngc.nvidia.com,"
    error "then run:  docker login nvcr.io"
  fi
  error "docker compose pull failed for ${VLLM_IMAGE} (see output above)."
}
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
  step "Waiting for vLLM to respond (timeout: ${VLLM_HEALTH_TIMEOUT}s)"
  info "Large models (NVFP4 100B+) can take 10–15 min to load weights."

  if [[ "$VLLM_TRAEFIK" == "true" ]]; then
    info "Traefik mode: skipping direct health check (access via https://${VLLM_DOMAIN})."
  else
    INTERVAL=10
    ELAPSED=0
    READY=false

    while [[ $ELAPSED -lt $VLLM_HEALTH_TIMEOUT ]]; do
      if curl -sf "http://localhost:${VLLM_PORT}/health" &>/dev/null; then
        READY=true; break
      fi
      echo -ne "\r    Waited ${ELAPSED}s / ${VLLM_HEALTH_TIMEOUT}s …"
      sleep $INTERVAL
      ELAPSED=$((ELAPSED + INTERVAL))
    done
    echo ""

    if [[ "$READY" == "true" ]]; then
      success "vLLM is up and healthy!"

      # ── Warmup: absorb the JIT cold-start (Inductor/FlashInfer ~25 s)
      # so the first real user request is fast.
      if [[ "$WARMUP" -eq 1 ]]; then
        WARMUP_MODEL="${VLLM_SERVED_MODEL_NAME:-${VLLM_MODEL}}"
        info "Sending warmup request (first request triggers JIT compilation, ~25 s)…"
        if curl -sf --max-time 600 -X POST "http://localhost:${VLLM_PORT}/v1/chat/completions" \
          -H "Content-Type: application/json" \
          -d "$(printf '{"model":"%s","max_tokens":3,"messages":[{"role":"user","content":"ping"}]}' "${WARMUP_MODEL}")" \
          &>/dev/null; then
          success "Warmup complete — the server is ready for real requests."
        else
          warn "Warmup request failed or timed out — the server may still be warming up."
          warn "Follow logs: cd ${PROJECT_DIR} && docker compose logs -f"
        fi
      fi
    else
      warn "vLLM did not respond within ${VLLM_HEALTH_TIMEOUT}s – it may still be loading the model."
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
echo -e "  ${BOLD}vLLM cache:${RESET}    ${VLLM_CACHE_DIR}  →  /root/.cache/vllm (compile cache)"
if [[ "$BACKEND" != "cpu" && -n "${VLLM_GPU_UTIL}" ]]; then
  echo -e "  ${BOLD}GPU util:${RESET}      ${VLLM_GPU_UTIL}"
fi
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
if [[ -n "${VLLM_SERVED_MODEL_NAME}" ]]; then
  echo -e "  ${BOLD}Served as:${RESET}     ${VLLM_SERVED_MODEL_NAME}"
fi
if [[ -n "${VLLM_REASONING_PARSER}" || -n "${VLLM_TOOL_CALL_PARSER}" || "${VLLM_ENABLE_AUTO_TOOL_CHOICE}" == "true" ]]; then
  echo -e "  ${BOLD}Agent serving:${RESET} enabled (reasoning-parser: ${VLLM_REASONING_PARSER:-—}, tool-call-parser: ${VLLM_TOOL_CALL_PARSER:-—}, auto-tool-choice: ${VLLM_ENABLE_AUTO_TOOL_CHOICE})"
fi
echo -e "  ${BOLD}LM Studio:${RESET}     ${LMSTUDIO_MODELS_DIR}  →  /lmstudio-models (in container)"
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

if [[ "$BACKEND" == "nvidia" ]] && is_spark; then
  echo ""
  echo -e "  ${BOLD}Model fit (DGX Spark, 128 GB unified memory):${RESET}"
  echo -e "  100–130B MoE NVFP4 (~10–15B active) is the best fit; up to ~200B NVFP4"
  echo -e "  fits the pool; dense models are poorly matched."
  echo -e "  Matrix: https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/vllm/README.md"
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
echo -e "  ${BOLD}Metrics (Prometheus — KV cache usage, TTFT/ITL histograms):${RESET}"
echo -e "    curl http://localhost:${VLLM_PORT}/metrics"
echo ""
echo -e "  ${BOLD}Change the model:${RESET} edit VLLM_MODEL in ${ENV_FILE},"
echo -e "  then: cd ${PROJECT_DIR} && docker compose up -d"
echo ""
echo -e "  ${BOLD}Download a model (on the host):${RESET}"
echo -e "    huggingface-cli download Qwen/Qwen2.5-7B-Instruct"
echo ""
