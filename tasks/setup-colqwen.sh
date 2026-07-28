#!/usr/bin/env bash
# shellcheck disable=SC1091
# =============================================================================
# setup-colqwen.sh
# Generates a ColQwen2.5 embedding-service Docker project under /srv/colqwen.
#
# The script only GENERATES the project - build and start it yourself:
#   cd /srv/colqwen && docker compose build && docker compose up -d
#
# Models are never downloaded and never baked into the image; they are
# mounted read-only from COLQWEN_MODEL_DIR. You are responsible for choosing
# compatible NGC PyTorch / colpali-engine versions (no validation happens).
#
# Usage:
#   ./setup-colqwen.sh                 # generate with defaults
#   ./setup-colqwen.sh --check         # show status and exit
#   ./setup-colqwen.sh --force         # re-generate over an existing project
#   ./setup-colqwen.sh --help          # show help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

TEMPLATE_DIR="${SCRIPT_DIR}/../templates/colqwen"

# ── Defaults ──────────────────────────────────────────────────────────────────
PROJECT_DIR="${PROJECT_DIR:-/srv/colqwen}"
COLQWEN_MODEL_DIR="${COLQWEN_MODEL_DIR:-}"   # empty = default (PROJECT_DIR/models)
COLQWEN_MODEL_NAME="${COLQWEN_MODEL_NAME:-colqwen2.5-v0.2}"
COLPALI_VERSION="${COLPALI_VERSION:-0.3.17}"
NGC_PYTORCH_TAG="${NGC_PYTORCH_TAG:-26.07-py3}"
COLQWEN_PORT="${COLQWEN_PORT:-8100}"

FORCE=0
CHECK_ONLY=0
WARNINGS=()

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}Usage:${RESET} $0 [OPTIONS]"
  echo ""
  echo "Generates a ColQwen2.5 embedding-service Docker project."
  echo "The service is NOT built or started - do that yourself afterwards:"
  echo "  cd ${PROJECT_DIR} && docker compose build && docker compose up -d"
  echo ""
  echo -e "${BOLD}Options:${RESET}"
  echo "  --dir <path>              Project directory  (default: /srv/colqwen)"
  echo "  --model-dir <path>        Host directory with the model directories,"
  echo "                            e.g. colqwen2.5-base/, colqwen2.5-v0.2/"
  echo "                            (default: <project dir>/models)"
  echo "  --model-name <name>       Model subdirectory to load  (default: colqwen2.5-v0.2)"
  echo "  --colpali-version <ver>   colpali-engine version  (default: 0.3.17)"
  echo "  --ngc-tag <tag>           NGC PyTorch base image tag  (default: 26.07-py3)"
  echo "  --port <n>                Host port for the service  (default: 8100)"
  echo "  --force                   Re-generate over an existing project"
  echo "  --check                   Show installation status and exit"
  echo "  --help                    Show this help"
  echo ""
  echo -e "${BOLD}Environment variables${RESET} (flag equivalents):"
  echo "  PROJECT_DIR, COLQWEN_MODEL_DIR, COLQWEN_MODEL_NAME,"
  echo "  COLPALI_VERSION, NGC_PYTORCH_TAG, COLQWEN_PORT"
  echo ""
  echo -e "${BOLD}Examples:${RESET}"
  echo "  $0                                        # generate with defaults"
  echo "  $0 --model-dir /srv/models --port 8101"
  echo "  $0 --ngc-tag 25.04-py3 --colpali-version 0.3.12"
  echo "  $0 --force                                # re-generate (.env backed up)"
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)              shift; PROJECT_DIR="$1" ;;
    --model-dir)        shift; COLQWEN_MODEL_DIR="$1" ;;
    --model-name)       shift; COLQWEN_MODEL_NAME="$1" ;;
    --colpali-version)  shift; COLPALI_VERSION="$1" ;;
    --ngc-tag)          shift; NGC_PYTORCH_TAG="$1" ;;
    --port)             shift; COLQWEN_PORT="$1" ;;
    --force)            FORCE=1 ;;
    --check)            CHECK_ONLY=1 ;;
    --help|-h)          usage ;;
    *) error "Unknown option: $1  (use --help for usage)" ;;
  esac
  shift
done

# Resolve the model dir default and remember whether it was user-provided.
MODEL_DIR_EXPLICIT=1
if [[ -z "$COLQWEN_MODEL_DIR" ]]; then
  COLQWEN_MODEL_DIR="${PROJECT_DIR}/models"
  MODEL_DIR_EXPLICIT=0
fi

# ── Input validation ──────────────────────────────────────────────────────────
# Values end up in .env via envsubst - restrict them to safe characters to
# prevent template injection.

validate_safe_string() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
    error "${name} contains invalid characters. Allowed: A-Z a-z 0-9 . _ -"
  fi
}

validate_abs_path() {
  local name="$1" value="$2"
  if [[ "$value" != /* ]]; then
    error "${name} must be an absolute path (got: ${value})"
  fi
}

validate_port() {
  if [[ ! "$COLQWEN_PORT" =~ ^[0-9]+$ || "$COLQWEN_PORT" -lt 1 || "$COLQWEN_PORT" -gt 65535 ]]; then
    error "COLQWEN_PORT must be a number between 1 and 65535 (got: ${COLQWEN_PORT})"
  fi
}

validate_abs_path  "PROJECT_DIR"        "$PROJECT_DIR"
validate_abs_path  "COLQWEN_MODEL_DIR"  "$COLQWEN_MODEL_DIR"
validate_safe_string "COLQWEN_MODEL_NAME" "$COLQWEN_MODEL_NAME"
validate_safe_string "COLPALI_VERSION"    "$COLPALI_VERSION"
validate_safe_string "NGC_PYTORCH_TAG"    "$NGC_PYTORCH_TAG"
validate_port

# ── Pre-flight checks ─────────────────────────────────────────────────────────
step "Pre-flight checks"

if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Run setup-docker.sh first."
fi
if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi
success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected and running."

COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "0.0.0")
if [[ "$(echo "$COMPOSE_VER" | cut -d'.' -f1)" -lt 2 ]]; then
  warn "Docker Compose v2+ recommended. Current: ${COMPOSE_VER}"
fi

if ! command -v envsubst &>/dev/null; then
  error "envsubst is not installed. Required for template rendering. Install with: sudo apt-get install gettext-base"
fi

# ── Existing installation / status ────────────────────────────────────────────
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"

print_status() {
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║   ColQwen project is already generated ✓     ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Project dir:${RESET}   ${PROJECT_DIR}"
  echo -e "  ${BOLD}Config:${RESET}        ${PROJECT_DIR}/.env"
  if docker compose -f "${COMPOSE_FILE}" ps --quiet 2>/dev/null | grep -q .; then
    echo -e "  ${BOLD}Status:${RESET}        ${GREEN}running${RESET}"
  else
    echo -e "  ${BOLD}Status:${RESET}        ${YELLOW}stopped${RESET}"
  fi
  echo ""
  echo -e "  ${CYAN}Nothing was changed.${RESET}"
  echo ""
}

step "Checking for existing ColQwen project"

if [[ -f "$COMPOSE_FILE" ]]; then
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    print_status
    exit 0
  fi
  if [[ "$FORCE" -eq 0 ]]; then
    print_status
    echo -e "  Use ${BOLD}--force${RESET} to re-generate the project (existing .env is backed up)."
    echo ""
    exit 0
  fi
  warn "--force specified - re-generating over the existing project."
else
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo ""
    echo -e "  ${YELLOW}ColQwen project is not generated yet.${RESET}"
    echo -e "  Run the script without ${BOLD}--check${RESET} to generate it."
    echo -e "  ${CYAN}Nothing was changed.${RESET}"
    echo ""
    exit 0
  fi
  success "No existing project found - proceeding with fresh generation."
fi

# ── Directories ───────────────────────────────────────────────────────────────
step "Creating directories"

if [[ ! -d "$PROJECT_DIR" ]]; then
  sudo mkdir -p "$PROJECT_DIR"
  sudo chown "${USER}:${USER}" "$PROJECT_DIR"
fi
mkdir -p "${PROJECT_DIR}/app"
success "Project dir: ${PROJECT_DIR}"

# ── Model directory handling ──────────────────────────────────────────────────
step "Checking model directory"

add_warning() {
  warn "$1"
  WARNINGS+=("$1")
}

if [[ ! -d "$COLQWEN_MODEL_DIR" ]]; then
  if [[ "$MODEL_DIR_EXPLICIT" -eq 0 ]]; then
    mkdir -p "$COLQWEN_MODEL_DIR"
    add_warning "Model directory ${COLQWEN_MODEL_DIR} was created empty - place your models there before starting the service."
  else
    add_warning "Model directory ${COLQWEN_MODEL_DIR} does not exist (typo?) - it was NOT created."
  fi
fi
if [[ ! -d "${COLQWEN_MODEL_DIR}/${COLQWEN_MODEL_NAME}" ]]; then
  add_warning "Configured model '${COLQWEN_MODEL_NAME}' not found in ${COLQWEN_MODEL_DIR} - the service will not start until it is present."
fi
if [[ ${#WARNINGS[@]} -eq 0 ]]; then
  success "Model found: ${COLQWEN_MODEL_DIR}/${COLQWEN_MODEL_NAME}"
fi

# ── Generate project files ────────────────────────────────────────────────────
step "Generating project files"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
  warn "Backing up existing .env to ${ENV_FILE}.bak"
  cp "$ENV_FILE" "${ENV_FILE}.bak"
fi

GENERATED_DATE="$(date -Iseconds)"
export NGC_PYTORCH_TAG COLPALI_VERSION COLQWEN_MODEL_DIR COLQWEN_MODEL_NAME \
  COLQWEN_PORT GENERATED_DATE
# shellcheck disable=SC2016  # envsubst expects the literal variable list
envsubst '${NGC_PYTORCH_TAG} ${COLPALI_VERSION} ${COLQWEN_MODEL_DIR} ${COLQWEN_MODEL_NAME} ${COLQWEN_PORT} ${GENERATED_DATE}' \
  < "${TEMPLATE_DIR}/env.template" > "$ENV_FILE"
chmod 600 "$ENV_FILE"
success ".env written (mode 600): ${ENV_FILE}"

cp "${TEMPLATE_DIR}/Dockerfile"         "${PROJECT_DIR}/Dockerfile"
cp "${TEMPLATE_DIR}/docker-compose.yml" "$COMPOSE_FILE"
cp "${TEMPLATE_DIR}/requirements.txt"   "${PROJECT_DIR}/requirements.txt"
cp "${TEMPLATE_DIR}/app/main.py"        "${PROJECT_DIR}/app/main.py"
success "Dockerfile, docker-compose.yml, requirements.txt and app/ written."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║      ColQwen project generated!              ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Project dir:${RESET}      ${PROJECT_DIR}"
echo -e "  ${BOLD}Model dir:${RESET}        ${COLQWEN_MODEL_DIR}  →  /models (read-only, in container)"
echo -e "  ${BOLD}Model:${RESET}            ${COLQWEN_MODEL_NAME}"
echo -e "  ${BOLD}NGC PyTorch tag:${RESET}  ${NGC_PYTORCH_TAG}"
echo -e "  ${BOLD}colpali-engine:${RESET}   ${COLPALI_VERSION}"
echo -e "  ${BOLD}Port:${RESET}             ${COLQWEN_PORT}"
echo -e "  ${BOLD}Config:${RESET}           ${ENV_FILE}"
echo ""
echo -e "${BOLD}Next steps${RESET} (the service was NOT built or started):"
echo -e "  cd ${PROJECT_DIR}"
echo -e "  docker compose build"
echo -e "  docker compose up -d"
echo ""
echo -e "${BOLD}Example requests:${RESET}"
echo -e "  curl -X POST http://localhost:${COLQWEN_PORT}/embed/queries \\\\"
echo -e "    -H 'Content-Type: application/json' -d '{\"queries\":[\"example query\"]}'"
echo -e "  curl -X POST http://localhost:${COLQWEN_PORT}/embed/images -F 'files=@page1.png'"
echo ""
echo -e "  Change configuration: edit ${ENV_FILE},"
echo -e "  then: cd ${PROJECT_DIR} && docker compose build && docker compose up -d"
echo ""

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "${BOLD}${YELLOW}Warnings:${RESET}"
  for w in "${WARNINGS[@]}"; do
    echo -e "  ${YELLOW}•${RESET} ${w}"
  done
  echo ""
fi
