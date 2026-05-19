#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# run-setup.sh — Orchestrator for machine setup automation
# =============================================================================
#
# DESCRIPTION:
#   Reads machine-config.yml to determine which setup scripts to run,
#   with their configured environment variables and command-line arguments.
#
# SUBCOMMANDS:
#   apply    Run all enabled setup scripts
#   status   Show which scripts are enabled/disabled
#
# USAGE:
#   ./run-setup.sh apply
#   ./run-setup.sh status
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_CONFIG_FILE="${SCRIPT_DIR}/machine-config.yml"
TASKS_DIR="${SCRIPT_DIR}/tasks"
CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
LOG_PREFIX="[RUN-SETUP]"

# Colors (default to empty for non-interactive terminals)
readonly BOLD="${BOLD:-}"
readonly RESET="${RESET:-}"
readonly RED="${RED:-}"
readonly GREEN="${GREEN:-}"
readonly YELLOW="${YELLOW:-}"
readonly CYAN="${CYAN:-}"

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_info()    { printf '%b %b %b  %s\n' "${LOG_PREFIX}" "${CYAN}[INFO]${RESET}" "" "$*"; }
log_success() { printf '%b %b %b    %s\n' "${LOG_PREFIX}" "${GREEN}[OK]${RESET}" "" "$*"; }
log_warn()    { printf '%b %b %b  %s\n' "${LOG_PREFIX}" "${YELLOW}[WARN]${RESET}" "" "$*"; }
log_error()   { printf '%b %b %b %s\n' "${LOG_PREFIX}" "${RED}[ERROR]${RESET}" "" "$*" >&2; }
log_step()    { printf '\n%b %b %s\n' "${BOLD}${LOG_PREFIX} ▶" "" "$*${RESET}"; }

# ─────────────────────────────────────────────────────────────────────────────
# Dependency Checks
# ─────────────────────────────────────────────────────────────────────────────

check_dependencies() {
  local missing=0
  
  if ! command -v yq &>/dev/null; then
    log_error "yq is not installed. Run setup-basics.sh first."
    missing=1
  fi
  
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_error "Hint: copy machine-config.yml.example to machine-config.yml"
    missing=1
  fi
  
  if [[ ! -d "$TASKS_DIR" ]]; then
    log_error "Tasks directory not found: $TASKS_DIR"
    missing=1
  fi
  
  if (( missing )); then
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# discover_scripts
#   Finds all setup scripts in the tasks directory.
#   Returns all script names (without path, sorted alphabetically),
#   regardless of whether they are executable.
# ─────────────────────────────────────────────────────────────────────────────

# shellcheck disable=SC2120  # pattern param unused but kept for extensibility
discover_scripts() {
  local pattern="${1:-*.sh}"

  if [[ ! -d "$TASKS_DIR" ]]; then
    log_error "Tasks directory not found: $TASKS_DIR" >&2
    return 1
  fi

  (
    shopt -s nullglob
    cd "$TASKS_DIR" || exit 1
    for script in $pattern; do
      if [[ -f "$script" ]]; then
        basename "$script"
      fi
    done
  ) | sort
}

# ─────────────────────────────────────────────────────────────────────────────
# is_script_enabled
#   Checks if a script is enabled in the config.
#   Returns 0 if enabled, 1 if disabled/not found.
# ─────────────────────────────────────────────────────────────────────────────

is_script_enabled() {
  local script_name="${1%.sh}"

  # shellcheck disable=SC2016  # $name is a jq variable, not bash
  yq --arg name "$script_name" '.scripts[$name].enabled // false' "$CONFIG_FILE" | grep -qx "true"
}

# ─────────────────────────────────────────────────────────────────────────────
# get_script_env
#   Prints environment variables for a script, one per line as KEY=VALUE.
# ─────────────────────────────────────────────────────────────────────────────

get_script_env() {
  local script_name="${1%.sh}"

  # shellcheck disable=SC2016  # $name is a jq variable, not bash
  yq -r --arg name "$script_name" \
    '.scripts[$name].env // {} | to_entries[] | "\(.key)=\(.value)"' \
    "$CONFIG_FILE" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# get_script_args
#   Prints command-line arguments for a script, one per line.
# ─────────────────────────────────────────────────────────────────────────────

get_script_args() {
  local script_name="${1%.sh}"

  # shellcheck disable=SC2016  # $name is a jq variable, not bash
  yq -r --arg name "$script_name" \
    '.scripts[$name].args // [] | .[]' \
    "$CONFIG_FILE" 2>/dev/null | grep -vE '^$|^null$' || true
}

# ─────────────────────────────────────────────────────────────────────────────
# get_script_description
#   Prints the description for a script.
# ─────────────────────────────────────────────────────────────────────────────

get_script_description() {
  local script_name="${1%.sh}"

  # shellcheck disable=SC2016  # $name is a jq variable, not bash
  yq -r --arg name "$script_name" \
    '.scripts[$name].description // ""' \
    "$CONFIG_FILE" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# cmd_status
#   Shows which scripts are enabled/disabled.
# ─────────────────────────────────────────────────────────────────────────────

cmd_status() {
  check_dependencies
  
  log_step "Checking configuration"
  echo
  
  printf '%bConfiguration: %s%b\n' "${BOLD}" "$CONFIG_FILE" "${RESET}"
  printf '%bTasks Directory: %s%b\n' "${BOLD}" "$TASKS_DIR" "${RESET}"
  echo
  
  # Validate config can be read
  local script_count
  script_count=$(yq '(.scripts | length) // 0' "$CONFIG_FILE")
  if [[ ! "$script_count" =~ ^[0-9]+$ ]] || (( script_count == 0)); then
    log_error "No scripts found in configuration"
    exit 1
  fi
  
  printf 'Scripts in config: %b%s%b\n' "${BOLD}" "$script_count" "${RESET}"
  echo
  
  local enabled_count=0
  enabled_count=$(yq '.scripts | to_entries | map(select(.value.enabled == true)) | length' "$CONFIG_FILE")
  if [[ "$enabled_count" =~ ^[0-9]+$ ]] && (( enabled_count > 0 )); then
    printf 'Enabled: %b%s%b\n' "${GREEN}" "$enabled_count" "${RESET}"
  else
    printf 'Enabled: %b%s%b\n' "${YELLOW}" "0" "${RESET}"
  fi
  
  local disabled_count=$((script_count - enabled_count))
  if [[ "$disabled_count" =~ ^[0-9]+$ ]] && (( disabled_count > 0 )); then
    printf 'Disabled: %b%s%b\n' "${CYAN}" "$disabled_count" "${RESET}"
  else
    printf 'Disabled: %b%s%b\n' "${CYAN}" "0" "${RESET}"
  fi
  
  echo
  
  # Show all scripts with their status
  printf '%bScript Status:%b\n' "${BOLD}" "${RESET}"
  echo
  
  # Discover scripts into an array (safe for names with spaces)
  local -a scripts_array=()
  local scripts_source
  # shellcheck disable=SC2119  # discover_scripts uses default pattern
  scripts_source=$(discover_scripts) || {
    log_warn "Could not discover scripts from $TASKS_DIR"
    scripts_source=$(yq '.scripts | keys | .[]' "$CONFIG_FILE")
  }
  while IFS= read -r line; do
    [[ -n "$line" ]] && scripts_array+=("$line")
  done <<< "$scripts_source"

  if (( ${#scripts_array[@]} == 0 )); then
    log_error "No scripts found"
    exit 1
  fi

  # Compute column width
  local max_len=0
  for script in "${scripts_array[@]}"; do
    local len=${#script}
    if (( len > max_len )); then
      max_len=$len
    fi
  done

  local line
  line=$(printf '%.0s─' $(seq 1 $((max_len + 30))))

  echo "$line"

  for script in "${scripts_array[@]}"; do
    local enabled="no"
    local color="${CYAN}"

    if is_script_enabled "$script"; then
      enabled="yes"
      color="${GREEN}"
    fi

    printf "  %-${max_len}s  %s\n" "$script" "$color$enabled$RESET"
  done

  echo "$line"

  echo

  # Show configured env vars and args for enabled scripts
  local first=true
  for script in "${scripts_array[@]}"; do
    if is_script_enabled "$script"; then
      if [[ -f "${TASKS_DIR}/${script}" ]]; then
        if [[ "$first" == "true" ]]; then
          printf '%bConfiguration for enabled scripts:%b\n' "${BOLD}" "${RESET}"
          first=false
        fi

        echo
        printf '%b  %s:%b\n' "${BOLD}" "$script" "${RESET}"

        local desc
        desc=$(get_script_description "$script")
        if [[ -n "$desc" ]]; then
          echo "    ${desc}"
        fi

        # Show env vars
        local env_vars
        env_vars=$(get_script_env "$script")
        if [[ -n "$env_vars" ]]; then
          echo "    Environment:"
          echo "${env_vars//$'\n'/\n      }"
        fi

        # Show args
        local args
        args=$(get_script_args "$script")
        if [[ -n "$args" ]]; then
          echo "    Arguments:"
          echo "${args//$'\n'/\n      }"
        fi
      fi
    fi
  done

  echo
}

# ─────────────────────────────────────────────────────────────────────────────
# run_script
#   Runs a single script with its configured environment and arguments.
#   Returns the exit code of the script.
# ─────────────────────────────────────────────────────────────────────────────

run_script() {
  local script_name="$1"
  local script_path="${TASKS_DIR}/${script_name}"
  
  if [[ ! -f "$script_path" ]]; then
    log_error "Script not found: $script_path"
    return 1
  fi
  
  if [[ ! -x "$script_path" ]]; then
    log_warn "Script not executable: $script_path"
    if ! chmod +x "$script_path"; then
      log_error "Cannot make script executable: $script_path"
      return 1
    fi
  fi
  
  log_step "Running ${script_name}"
  
  # Collect environment variables as KEY=VALUE strings
  local env_args=()
  while IFS= read -r env_pair; do
    [[ -n "$env_pair" ]] && env_args+=("$env_pair")
  done < <(get_script_env "$script_name")
  
  # Collect arguments
  local args=()
  while IFS= read -r arg; do
    [[ -n "$arg" ]] && args+=("$arg")
  done < <(get_script_args "$script_name")
  
  # Run the script with environment variables
  if [[ ${#env_args[@]} -gt 0 ]]; then
    env "${env_args[@]}" "$script_path" "${args[@]}"
  else
    "$script_path" "${args[@]}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# cmd_apply
#   Runs all enabled setup scripts.
# ─────────────────────────────────────────────────────────────────────────────

cmd_apply() {
  log_step "Applying configuration"
  
  check_dependencies
  
  echo
  log_info "Reading configuration from: $CONFIG_FILE"
  log_info "Scripts directory: $TASKS_DIR"
  echo
  
  # Check if any scripts are enabled
  local enabled_count=0
  enabled_count=$(yq '.scripts | to_entries | map(select(.value.enabled == true)) | length' "$CONFIG_FILE")
  
  if [[ ! "$enabled_count" =~ ^[0-9]+$ ]] || (( enabled_count == 0 )); then
    exit 0
  fi
  
  log_info "Found ${enabled_count} enabled script(s)"
  echo
  
  # shellcheck disable=SC2119  # discover_scripts uses default pattern
  # Discover scripts into an array (safe for names with spaces)
  local -a scripts_array=()
  local scripts_source
  scripts_source=$(discover_scripts) || {
    log_warn "Could not discover scripts from $TASKS_DIR"
    scripts_source=$(yq '.scripts | keys | .[]' "$CONFIG_FILE")
  }
  while IFS= read -r line; do
    [[ -n "$line" ]] && scripts_array+=("$line")
  done <<< "$scripts_source"

  # Run each enabled script
  local failed_count=0
  local skipped_count=0

  for script in "${scripts_array[@]}"; do
    if is_script_enabled "$script"; then
      local script_path="${TASKS_DIR}/${script}"

      if [[ ! -f "$script_path" ]]; then
        log_error "Configured script not found: $script"
        skipped_count=$((skipped_count + 1))
        continue
      fi

      echo
      if run_script "$script"; then
        log_success "Completed: $script"
      else
        log_error "Failed: $script"
        ((++failed_count))
      fi
    fi
  done
  
  # Report results
  echo
  echo
  log_step "Run Summary"
  
  local total_enabled=$enabled_count
  local success_count=$((total_enabled - failed_count - skipped_count))
  
  if (( success_count == total_enabled )) && (( success_count > 0 )); then
    log_success "All $success_count script(s) completed successfully"
  else
    if (( success_count > 0 )); then
      log_info "Succeeded: $success_count/$total_enabled"
    fi
    
    if (( skipped_count > 0 )); then
      log_warn "Skipped: $skipped_count/$total_enabled (scripts missing from disk)"
    fi
    
    if (( failed_count > 0 )); then
      log_error "Failed: $failed_count/$total_enabled"
      echo
      log_info "Check logs above for details"
      exit 1
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# cmd_help
#   Shows usage information.
# ─────────────────────────────────────────────────────────────────────────────

cmd_help() {
  cat <<'EOF'

  Machine Setup Automation Runner

  Usage: ./run-setup.sh <subcommand> [options]

  Subcommands:
    apply    Run all enabled setup scripts
    status   Show which scripts are enabled/disabled

  Options:
    -c, --config <file>  Path to configuration file (default: machine-config.yml)
    -h, --help           Show this help message

  Examples:
    ./run-setup.sh status
    ./run-setup.sh apply
    ./run-setup.sh --config my-config.yml apply

  Configuration:
    Edit machine-config.yml to enable/disable scripts and configure
    their environment variables and command-line arguments.

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────────────────────

main() {
  # Parse options
  local config_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        if [[ -z "${2:-}" ]]; then
          log_error "--config requires a value"
          exit 1
        fi
        config_file="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  # Resolve config file
  if [[ -n "$config_file" ]]; then
    if [[ "$config_file" != /* ]]; then
      CONFIG_FILE="$(cd "$(pwd)" && cd "$(dirname "$config_file")" && pwd)/$(basename "$config_file")"
    else
      CONFIG_FILE="$config_file"
    fi
  else
    CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
  fi

  # Parse subcommand from remaining args
  local subcommand="${1:-}"
  case "$subcommand" in
    apply)
      shift
      cmd_apply "$@"
      ;;
    status)
      shift
      cmd_status "$@"
      ;;
    help|--help|-h|"")
      cmd_help
      exit 0
      ;;
    *)
      printf '%b %b %b %s\n' "${RED}[ERROR]${RESET}" "${RED}[ERROR]${RESET}" "" "Unknown subcommand: $subcommand" >&2
      echo
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"