#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/helpers.sh — Shared helper library for machine_setup_automation
# =============================================================================
#
# PURPOSE:
#   Provides common colour variables, logging functions, and pre-flight check
#   helpers that are reused across multiple setup scripts in this project.
#
# USAGE:
#   Source this file at the top of any setup script:
#     source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"
#   or with an absolute path:
#     source /path/to/machine_setup_automation/lib/helpers.sh
#
# NOTES:
#   - This file is designed to be *sourced*, not executed directly.
#   - All definitions are guarded so re-sourcing is safe and user additions
#   - made after the initial source will not be overwritten.
#   - No `set -eu` here; the calling script controls those options.
# =============================================================================

# ---------------------------------------------------------------------------
# Colour variables (guarded — skip if already defined)
# ---------------------------------------------------------------------------
if [[ -z "${RED:-}" ]];    then RED=$'\033[0;31m';    fi
if [[ -z "${GREEN:-}" ]];  then GREEN=$'\033[0;32m';  fi
if [[ -z "${YELLOW:-}" ]]; then YELLOW=$'\033[1;33m'; fi
if [[ -z "${CYAN:-}" ]];   then CYAN=$'\033[0;36m';   fi
if [[ -z "${BOLD:-}" ]];   then BOLD=$'\033[1m';      fi
if [[ -z "${RESET:-}" ]];  then RESET=$'\033[0m';     fi

# ---------------------------------------------------------------------------
# Logging helpers (guarded — skip if already defined)
# ---------------------------------------------------------------------------
if ! declare -F step > /dev/null 2>&1; then
  step() { echo -e "\n${BOLD}▶ $*${RESET}"; }
fi

if ! declare -F info > /dev/null 2>&1; then
  info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
fi

if ! declare -F success > /dev/null 2>&1; then
  success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
fi

if ! declare -F warn > /dev/null 2>&1; then
  warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
fi

if ! declare -F error > /dev/null 2>&1; then
  error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
fi

# ---------------------------------------------------------------------------
# run_preflight_checks
#   Validates all required dependencies are available before setup proceeds.
#   Checks: Docker installation, Docker daemon running, OpenSSL, curl.
# ---------------------------------------------------------------------------
if ! declare -F run_preflight_checks > /dev/null 2>&1; then
  run_preflight_checks() {
    # Check Docker is installed
    if ! command -v docker &>/dev/null; then
      echo -e "${RED}[ERROR]${RESET} Docker is not installed. Please run setup-docker.sh first." >&2
      exit 1
    fi
    
    # Check Docker daemon is running
    if ! docker info &>/dev/null; then
      echo -e "${RED}[ERROR]${RESET} Docker daemon is not running. Please start Docker." >&2
      exit 1
    fi
    
    # Check OpenSSL is available
    if ! command -v openssl &>/dev/null; then
      echo -e "${RED}[ERROR]${RESET} OpenSSL is not installed. Required for password and key generation." >&2
      exit 1
    fi
    
    # Check curl is available
    if ! command -v curl &>/dev/null; then
      echo -e "${RED}[ERROR]${RESET} curl is not installed. Required for health check polling." >&2
      exit 1
    fi
  }
fi

# ---------------------------------------------------------------------------
# ensure_proxy_network
#   Verifies that the Docker network referenced by PROXY_NETWORK exists.
#   Exits 1 if the network is absent.
# ---------------------------------------------------------------------------
if ! declare -F ensure_proxy_network > /dev/null 2>&1; then
  ensure_proxy_network() {
    local network="${PROXY_NETWORK:-proxy}"
    if docker network ls --format '{{.Name}}' | grep -qx "${network}"; then
      success "Docker network '${network}' exists."
    else
      echo -e "${RED}[ERROR]${RESET} Docker network '${network}' not found." >&2
      echo -e "${RED}[ERROR]${RESET} Please run setup-traefik.sh first to create it." >&2
      exit 1
    fi
  }
fi

# ---------------------------------------------------------------------------
# ensure_traefik_running
#   Verifies that a Docker container named 'traefik' is currently running.
#   Exits 1 if the container is not found among running containers.
# ---------------------------------------------------------------------------
if ! declare -F ensure_traefik_running > /dev/null 2>&1; then
  ensure_traefik_running() {
    if docker ps --format '{{.Names}}' | grep -qx 'traefik'; then
      success "Traefik container is running."
    else
      echo -e "${RED}[ERROR]${RESET} Traefik container is not running." >&2
      echo -e "${RED}[ERROR]${RESET} Please start Traefik first before running this script." >&2
      exit 1
    fi
  }
fi

# ---------------------------------------------------------------------------
# detect_arch
#   Detects the host architecture and maps it to the standard Go/OS
#   architecture name (amd64 or arm64). Exits on unsupported arch.
#
# OUTPUT:
#   Prints 'amd64' or 'arm64' to stdout.
# ---------------------------------------------------------------------------
if ! declare -F detect_arch > /dev/null 2>&1; then
  detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
      x86_64)  echo "amd64" ;;
      aarch64|arm64) echo "arm64" ;;
      *)       error "Unsupported architecture: ${arch}. Only amd64 and arm64 are supported." ;;
    esac
  }
fi

# ---------------------------------------------------------------------------
# mktempfile
#   Creates a temporary file and returns its path. Uses mktemp with a
#   predictable naming pattern for easier debugging. File is not deleted
#   automatically - caller is responsible for cleanup.
# ---------------------------------------------------------------------------
if ! declare -F mktempfile > /dev/null 2>&1; then
  mktempfile() {
    mktemp -t "$(basename "$1" | sed 's/$/.XXXXXX/')" 2>/dev/null || mktemp -t "tmp.XXXXXX"
  }
fi