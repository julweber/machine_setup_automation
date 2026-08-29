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
# Error semantics
#
# RULE: `error` and `die` terminate the process — never call them inside a
#       command substitution that a caller guards with `||` (the exit would
#       only kill the subshell and the guarded fallback would silently take
#       effect). Use `err_msg` + `return` in helpers that must be
#       recoverable, so the caller can decide how to handle the failure.
# ---------------------------------------------------------------------------

# Report an error, do NOT exit. Use inside functions/helpers whose caller decides.
if ! declare -F err_msg > /dev/null 2>&1; then
  err_msg() { echo -e "${RED}[ERROR]${RESET} $*" >&2; return 1; }
fi

# Terminal error: report and exit. Identical semantics to error().
if ! declare -F die > /dev/null 2>&1; then
  die() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
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
# detect_arch [fallback]
#   Detects the host architecture and maps it to the standard Go/OS
#   architecture name (amd64 or arm64).
#
#   Prints 'amd64' or 'arm64'. On an unsupported arch: prints an error to
#   stderr and returns 1 (printing [fallback] first, if one was given).
#   Never exits, so callers can decide.
#
#   Callers under `set -euo pipefail` should use the assignment-with-return
#   shape so the failure stays loud (err_msg already printed the reason):
#     ARCH="$(detect_arch)" || exit 1
#   (A bare `ARCH="$(detect_arch)"` also aborts the script on failure, which
#   is fine — but never guard it with `|| <fallback>`, that would hide the
#   error and silently install artifacts for the wrong architecture.)
#
# OUTPUT:
#   Prints 'amd64' or 'arm64' to stdout.
# ---------------------------------------------------------------------------
if ! declare -F detect_arch > /dev/null 2>&1; then
  detect_arch() {
    local fallback="${1:-}" arch
    arch="$(uname -m)"
    case "$arch" in
      x86_64)            echo "amd64"; return 0 ;;
      aarch64|arm64)     echo "arm64"; return 0 ;;
      *)
        err_msg "Unsupported architecture: ${arch}. Only amd64 and arm64 are supported."
        [[ -n "$fallback" ]] && echo "$fallback"
        return 1
        ;;
    esac
  }
fi

# ---------------------------------------------------------------------------
# mktempfile <name>
#   Creates a temporary file and prints its path. Uses mktemp with a
#   predictable naming pattern (suffix of <name>) for easier debugging,
#   falling back to an unnamed temp file.
#
#   Cleanup: files created via mktempfile are removed automatically when the
#   sourcing script exits, and the caller's own EXIT trap is preserved. The
#   cleanup is *chained* onto any EXIT trap the calling script installed, so
#   task-level cleanup (docker compose down on failure) still runs.
#
#   How it works: file names are recorded in a per-process tracking file
#   ($_MKTEMP_TRACK_FILE) rather than a shell variable, because mktempfile is
#   normally called inside a command substitution (f="$(mktempfile x.sh)"),
#   which runs in a subshell — there, neither variable updates nor EXIT
#   traps reach the parent shell. The cleanup trap is armed in the parent
#   (at source time, and on any direct non-subshell call) and reads the
#   tracking file on exit.
#
#   Limitations:
#   - Trap chaining re-reads the existing EXIT trap via `trap -p`, which
#     loses quoting for traps containing single quotes. None of the existing
#     task EXIT traps do (they call `cleanup_on_failure`).
#   - A script that installs its own EXIT trap *after* sourcing this library
#     (plain `trap ... EXIT`) replaces the chained trap. No current task
#     script both does that and uses mktempfile; if one appears, it must
#     include `_mktemp_cleanup` in its own trap.
# ---------------------------------------------------------------------------
if [[ -z "${_MKTEMP_TRACK_FILE:-}" ]]; then
  _MKTEMP_TRACK_FILE="${TMPDIR:-/tmp}/msa-mktempfile-tracker.$$"
fi

if ! declare -F _mktemp_cleanup > /dev/null 2>&1; then
  # Remove every temp file recorded via mktempfile, then the tracker itself.
  _mktemp_cleanup() {
    local _f
    if [[ -f "${_MKTEMP_TRACK_FILE:-}" ]]; then
      while IFS= read -r _f; do
        [[ -n "$_f" ]] && rm -f -- "$_f"
      done < "${_MKTEMP_TRACK_FILE}"
      rm -f -- "${_MKTEMP_TRACK_FILE}"
    fi
    return 0
  }
fi

if ! declare -F _mktemp_arm_exit_trap > /dev/null 2>&1; then
  # Chain _mktemp_cleanup onto the current EXIT trap without overwriting it.
  # No-op when the cleanup is already part of the trap, so repeated
  # mktempfile calls never re-wrap it.
  _mktemp_arm_exit_trap() {
    local _cur _prev
    _cur="$(trap -p EXIT)"
    if [[ "$_cur" == *"_mktemp_cleanup"* ]]; then
      return 0
    fi
    _prev="$(trap -p EXIT | sed -n "s/^trap -- '\(.*\)' EXIT$/\1/p")"
    if [[ -n "$_prev" ]]; then
      # Expand now on purpose: the handler is composed from the existing
      # handler string extracted above.
      # shellcheck disable=SC2064
      trap "_mktemp_cleanup; ${_prev}" EXIT
    else
      trap "_mktemp_cleanup" EXIT
    fi
  }
fi

# Arm the cleanup trap in the sourcing (parent) shell. Task scripts that
# install their own EXIT trap later take precedence; see limitations above.
_mktemp_arm_exit_trap

if ! declare -F mktempfile > /dev/null 2>&1; then
  mktempfile() {
    local f
    f="$(mktemp -t "$(basename "$1" | sed 's/$/.XXXXXX/')" 2>/dev/null || mktemp -t "tmp.XXXXXX")" || return 1
    printf '%s\n' "$f" >> "${_MKTEMP_TRACK_FILE}"
    # Re-arm only in the top-level shell: inside a command substitution this
    # function runs in a subshell, where an armed EXIT trap would fire at
    # the end of the substitution — deleting the file before the caller has
    # used it (its output would be captured into the assignment).
    if [[ "${BASH_SUBSHELL:-0}" -eq 0 ]]; then
      _mktemp_arm_exit_trap
    fi
    printf '%s\n' "$f"
  }
fi

# ---------------------------------------------------------------------------
# is_apt_package_installed
#   Returns 0 if the given dpkg package is actually installed (status DB
#   reports 'installed'), 1 otherwise.
#
#   NOTE: Do NOT use `dpkg -l <pkg>` for this — it exits 0 for packages that
#   are merely known to apt (e.g. status 'un', available but not installed),
#   causing false positives.
# ---------------------------------------------------------------------------
if ! declare -F is_apt_package_installed > /dev/null 2>&1; then
  is_apt_package_installed() {
    local pkg="$1"
    dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null | grep -qx 'installed'
  }
fi

# ---------------------------------------------------------------------------
# UFW Firewall Helpers
#   Provides common functions for managing UFW firewall rules.
#
#   `ufw status` is always read through ufw_status_text(), which caches its
#   result in _UFW_STATUS for the lifetime of the shell, so a task with N
#   rules does not shell out N times. The cache is invalidated after every
#   successful rule mutation (ufw allow / ufw delete) so readers never see
#   stale state.
#
#   NOTE: IPv6 rules are rendered differently by `ufw status`; the direction
#   check in ufw_rule_exists only covers the classic IPv4
#   `port/proto  ALLOW IN|OUT` lines.
# ---------------------------------------------------------------------------

# ufw_status_text() result cache (empty _UFW_STATUS_RC = not read yet).
# Guarded so re-sourcing this library is a no-op (does not drop a warm cache).
if [[ -z "${_UFW_STATUS_RC+x}" ]]; then
  _UFW_STATUS=""
  _UFW_STATUS_RC=""
fi

if ! declare -F ufw_available > /dev/null 2>&1; then
  ufw_available() {
    command -v ufw &>/dev/null
  }
fi

if ! declare -F ufw_status_text > /dev/null 2>&1; then
  # ufw_status_text
  #   Prints machine-readable `ufw status` output. Returns:
  #     0 = readable (active or inactive)
  #     1 = ufw binary present but status could not be read (sudo denied, error, ...)
  #     2 = ufw not installed
  #   The result is cached in _UFW_STATUS for the lifetime of the shell;
  #   _ufw_invalidate_status_cache() clears it after rule mutations.
  ufw_status_text() {
    if [[ -n "${_UFW_STATUS_RC}" ]]; then
      if [[ "${_UFW_STATUS_RC}" == "0" ]]; then
        printf '%s\n' "${_UFW_STATUS}"
      fi
      return "${_UFW_STATUS_RC}"
    fi

    if ! command -v ufw &>/dev/null; then
      _UFW_STATUS_RC=2
      return 2
    fi

    local out err err_file
    # Try non-interactive sudo (-n) first so a password prompt can never hang
    # a setup script. On failure, fall back to a possibly-interactive sudo
    # only when the failure was not a password requirement (which would just
    # prompt again or fail the same way).
    err_file="$(mktemp)"
    if out="$(sudo -n ufw status 2>"${err_file}")" && grep -q "^Status:" <<<"$out"; then
      rm -f -- "${err_file}"
      _UFW_STATUS="$out"
      _UFW_STATUS_RC=0
      printf '%s\n' "${_UFW_STATUS}"
      return 0
    fi
    err="$(cat -- "${err_file}")"
    rm -f -- "${err_file}"
    if [[ "${err,,}" == *"password"* ]]; then
      _UFW_STATUS_RC=1
      return 1
    fi
    if out="$(sudo ufw status 2>/dev/null)" && grep -q "^Status:" <<<"$out"; then
      _UFW_STATUS="$out"
      _UFW_STATUS_RC=0
      printf '%s\n' "${_UFW_STATUS}"
      return 0
    fi
    _UFW_STATUS_RC=1
    return 1
  }
fi

if ! declare -F _ufw_invalidate_status_cache > /dev/null 2>&1; then
  # Drop the cached `ufw status` output. Called after a successful rule
  # mutation (ufw allow / ufw delete) so the next read sees the new state.
  _ufw_invalidate_status_cache() {
    _UFW_STATUS=""
    _UFW_STATUS_RC=""
  }
fi

if ! declare -F ufw_active > /dev/null 2>&1; then
  # ufw_active
  #   Returns: 0 = active, 1 = inactive-but-known, 2 = unknown (could not read).
  ufw_active() {
    local status
    if ! status="$(ufw_status_text)"; then
      return 2
    fi
    grep -q "^Status: active" <<<"$status"
  }
fi

if ! declare -F ufw_rule_exists > /dev/null 2>&1; then
  # ufw_rule_exists <port> [proto] [direction]
  #   Returns 0 when a rule for port/proto in the given direction (default IN)
  #   exists. An ALLOW OUT rule never satisfies an ALLOW IN lookup. Returns 1
  #   when the rule is absent or the status could not be read.
  ufw_rule_exists() {
    local port="$1" proto="${2:-tcp}" direction="${3:-IN}"
    local status
    status="$(ufw_status_text)" || return 1
    # Direction-aware: an ALLOW OUT rule must not satisfy an ALLOW IN lookup.
    # Numbered/verbose output prefixes rules with "[  1]", so allow for it.
    grep -qE "^[[:space:]]*(\[[[:space:]]*[0-9]+\][[:space:]]*)?${port}/${proto}[[:space:]]+ALLOW[[:space:]]+${direction}([[:space:]]|$)" <<<"$status"
  }
fi

if ! declare -F ufw_add_rule > /dev/null 2>&1; then
  ufw_add_rule() {
    local port="$1"
    local proto="${2:-tcp}"
    local comment="${3:-}"
    local status_rc=0

    # Unreadable status (sudo denied, ufw error, ...) is a hard failure:
    # refuse to assume the rule is present and name the remedy.
    ufw_status_text >/dev/null || status_rc=$?
    if (( status_rc != 0 )); then
      err_msg "Cannot read 'ufw status' (rc=${status_rc}) — refusing to assume rules are present." || true
      err_msg "Fix passwordless sudo for ufw, or run: sudo ufw allow ${port}/${proto}" || true
      return 1
    fi

    if ufw_rule_exists "$port" "$proto" IN; then
      info "Inbound rule for ${port}/${proto} already exists, skipping."
      return 0
    fi

    if [[ -n "$comment" ]]; then
      sudo ufw allow "${port}/${proto}" comment "${comment}"
    else
      sudo ufw allow "${port}/${proto}"
    fi
    _ufw_invalidate_status_cache
    success "UFW rule added: ${port}/${proto}"
  }
fi

if ! declare -F ufw_delete_rule > /dev/null 2>&1; then
  ufw_delete_rule() {
    local port="$1"
    local proto="${2:-tcp}"

    # `ufw delete allow <port>/<proto>` removes the INBOUND rule only;
    # outbound (ALLOW OUT) rules are not touched.
    sudo ufw delete allow "${port}/${proto}" 2>/dev/null || true
    _ufw_invalidate_status_cache
    success "UFW rule removed: ${port}/${proto}"
  }
fi

if ! declare -F ufw_enable > /dev/null 2>&1; then
  ufw_enable() {
    if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
      success "UFW is already active."
      return 0
    fi

    sudo ufw --force enable
    success "UFW enabled."
  }
fi

if ! declare -F ufw_show_status > /dev/null 2>&1; then
  ufw_show_status() {
    sudo ufw status
  }
fi

if ! declare -F ufw_firewall_section > /dev/null 2>&1; then
  ufw_firewall_section() {
    local description="${1:-firewall}"
    shift
    # Remaining args are port/proto/comment triples: port proto comment port proto comment ...

    step "Configuring UFW ${description}"

    if ! ufw_available; then
      warn "UFW not installed — skipping ${description} configuration."
      return 0
    fi

    # 0 = active, 1 = inactive-but-known, 2 = unknown (could not read).
    local active=0
    ufw_active || active=$?
    if (( active == 2 )); then
      # Present-but-unreadable UFW is a hard failure: a service task must not
      # silently skip protection.
      error "UFW is installed but its status could not be read — cannot verify that ${description} ports are open. Fix sudo access to ufw (passwordless 'sudo ufw status') and re-run."
    fi
    if (( active == 1 )); then
      warn "UFW is inactive — ${description} rules added below will take effect when the firewall is enabled (configure-firewall.sh)."
    fi

    while [[ $# -ge 3 ]]; do
      local port="$1"
      local proto="${2:-tcp}"
      local comment="${3:-}"
      shift 3
      ufw_add_rule "$port" "$proto" "$comment"
    done
  }
fi