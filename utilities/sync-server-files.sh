#!/bin/bash
# =============================================================================
# sync-server-files.sh — Sync a directory from a remote server via rsync
# =============================================================================
#
# Description:
#   Syncs one directory from a remote server to the local machine using
#   rsync over SSH. Handles Docker volume ownership (UID 10000) gracefully
#   by stripping ownership metadata on the destination.
#
#   Performs incremental (rsync-style) sync — only changed files are
#   transferred. To sync multiple directories, invoke this script once per
#   directory with different --source-directory/--target-directory values.
#
# Options:
#   --source-directory <path>   Remote directory on the server to sync (required)
#   --target-directory <path>   Local directory to sync into (required)
#   --dry-run                   Show what would be transferred without doing it
#   --verbose                   Show rsync output in detail
#   --sudo                      Use sudo on remote side for reading restricted files
#   --help                      Show help and exit
#
# Environment Variables:
#   SYNC_REMOTE_USER   SSH user on the server (required)
#   SYNC_REMOTE_HOST   Server IP or hostname  (required)
#   SYNC_SSH_PORT      SSH port               (default: 2224)
#   SYNC_DELETE        Delete local files not on remote ("yes" to enable)
#   SYNC_SUDO          Use sudo on remote side ("yes" to enable; also --sudo)
#
# Usage:
#   SYNC_REMOTE_USER=alice SYNC_REMOTE_HOST=192.168.1.100 \
#     ./sync-server-files.sh --source-directory /srv/hermes --target-directory ~/backups/hermes
#   SYNC_REMOTE_HOST=192.168.1.100 SYNC_DELETE=yes \
#     ./sync-server-files.sh --source-directory /srv/openwebui --target-directory ~/backups/openwebui
#   SYNC_REMOTE_HOST=192.168.1.100 SYNC_SUDO=yes \
#     ./sync-server-files.sh --source-directory /srv/forgejo --target-directory ~/backups/forgejo --sudo
#   ./sync-server-files.sh --source-directory /srv/hermes --target-directory ~/backups/hermes --dry-run
#
# Sudo Configuration (required when using --sudo or SYNC_SUDO=yes):
#   Since rsync runs over SSH without a tty, sudo cannot prompt for a password
#   interactively. Configure passwordless sudo for rsync on the remote server:
#
#     sudo visudo
#     # Add the following line (adjust username as needed):
#     alice ALL=(ALL) NOPASSWD: /usr/bin/rsync
#
#   This only grants passwordless access to rsync, not to arbitrary commands.
#   For tighter restrictions, limit to specific paths:
#     alice ALL=(ALL) NOPASSWD: /usr/bin/rsync --server * /srv/hermes
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

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
print_help() {
  cat <<EOF
Usage: $0 --source-directory <remote-path> --target-directory <local-path> [OPTIONS]

Sync one directory from a remote server to the local machine via rsync.

Required options:
  --source-directory <path>   Remote directory on the server to sync
  --target-directory <path>   Local directory to sync into

Options:
  --help       Show this help message and exit
  --dry-run    Show what would be transferred without doing it
  --verbose    Show rsync output in detail
  --sudo       Use sudo on remote side for reading restricted files

Environment Variables:
  SYNC_REMOTE_USER   SSH user on the server    (required)
  SYNC_REMOTE_HOST   Server IP or hostname    (required)
  SYNC_SSH_PORT      SSH port                 (default: 2224)
  SYNC_DELETE        Delete local files not on remote ("yes" to enable)
  SYNC_SUDO          Use sudo on remote side ("yes" to enable)

Examples:
  SYNC_REMOTE_USER=alice SYNC_REMOTE_HOST=192.168.1.100 $0 --source-directory /srv/hermes --target-directory ~/backups/hermes
  SYNC_REMOTE_HOST=192.168.1.100 SYNC_DELETE=yes $0 --source-directory /srv/openwebui --target-directory ~/backups/openwebui
  SYNC_REMOTE_HOST=192.168.1.100 $0 --source-directory /srv/forgejo --target-directory ~/backups/forgejo --dry-run --verbose
  SYNC_REMOTE_HOST=192.168.1.100 SYNC_SUDO=yes $0 --source-directory /srv/forgejo --target-directory ~/backups/forgejo --sudo
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments (before config so --help works without SYNC_REMOTE_HOST)
# ---------------------------------------------------------------------------
SOURCE_DIRECTORY=""
TARGET_DIRECTORY=""
RSYNC_EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      print_help
      exit 0
      ;;
    --source-directory)
      if [[ $# -lt 2 ]]; then
        error "--source-directory requires a value. Run $0 --help for usage information."
      fi
      SOURCE_DIRECTORY="$2"
      shift 2
      ;;
    --target-directory)
      if [[ $# -lt 2 ]]; then
        error "--target-directory requires a value. Run $0 --help for usage information."
      fi
      TARGET_DIRECTORY="$2"
      shift 2
      ;;
    --dry-run)
      RSYNC_EXTRA_ARGS+=("--dry-run")
      shift
      ;;
    --verbose)
      RSYNC_EXTRA_ARGS+=("-v")
      shift
      ;;
    --sudo)
      SYNC_SUDO="yes"
      shift
      ;;
    *)
      warn "Unknown argument: $1. Run $0 --help for usage information."
      shift
      ;;
  esac
done

if [[ -z "${SOURCE_DIRECTORY}" ]]; then
  error "--source-directory is required. Run $0 --help for usage information."
fi
if [[ -z "${TARGET_DIRECTORY}" ]]; then
  error "--target-directory is required. Run $0 --help for usage information."
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SYNC_REMOTE_USER="${SYNC_REMOTE_USER:?ERROR: SYNC_REMOTE_USER is not set. Export it or pass it via environment.}"
SYNC_REMOTE_HOST="${SYNC_REMOTE_HOST:?ERROR: SYNC_REMOTE_HOST is not set. Export it or pass it via environment.}"
SYNC_SSH_PORT="${SYNC_SSH_PORT:-2224}"
SYNC_DELETE="${SYNC_DELETE:-no}"
SYNC_SUDO="${SYNC_SUDO:-no}"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

# Check rsync is installed
if ! command -v rsync &>/dev/null; then
  error "rsync is not installed. Install it with: sudo apt install rsync"
fi

# Check ssh is reachable
if ! command -v ssh &>/dev/null; then
  error "ssh is not installed. Install it with: sudo apt install openssh-client"
fi

# Check remote host is reachable (quick ping check)
step "Checking connectivity to ${SYNC_REMOTE_USER}@${SYNC_REMOTE_HOST}:${SYNC_SSH_PORT}"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${SYNC_SSH_PORT}" "${SYNC_REMOTE_USER}@${SYNC_REMOTE_HOST}" "echo reachable" &>/dev/null; then
  error "Cannot reach ${SYNC_REMOTE_USER}@${SYNC_REMOTE_HOST}:${SYNC_SSH_PORT}. Check SSH access and network."
fi
success "Server is reachable"

# Check remote path exists
step "Checking remote path: ${SOURCE_DIRECTORY}"
if ! ssh -p "${SYNC_SSH_PORT}" "${SYNC_REMOTE_USER}@${SYNC_REMOTE_HOST}" "test -d '${SOURCE_DIRECTORY}'" &>/dev/null; then
  error "Remote directory does not exist: ${SOURCE_DIRECTORY}"
fi
success "Remote directory exists"

# Create local destination
step "Setting up local destination: ${TARGET_DIRECTORY}"
mkdir -p "${TARGET_DIRECTORY}"
success "Local destination ready"

# ---------------------------------------------------------------------------
# Build and run rsync
# ---------------------------------------------------------------------------

# rsync flags:
#   -a        archive mode (recursive, preserves perms, times, symlinks, etc.)
#   --no-owner --no-group  skip ownership — avoids Docker UID 10000 issues
#   -z        compress during transfer
#   --delete  remove local files that no longer exist remotely (opt-in)
#   --info=progress2  show progress
#   --stats   show transfer statistics at the end
RSYNC_FLAGS=(
  -a
  --no-owner
  --no-group
  -z
  --info=progress2
  --stats
)

# Add --delete if SYNC_DELETE is "yes"
if [[ "${SYNC_DELETE}" == "yes" ]]; then
  RSYNC_FLAGS+=("--delete")
  info "Sync will delete local files that no longer exist on the remote."
fi

# Build rsync command with optional sudo on remote side
# Build SSH connection string with port
SSH_EXTRA_ARGS=(-p "${SYNC_SSH_PORT}")

if [[ "${SYNC_SUDO}" == "yes" ]]; then
  RSYNC_CMD=(
    rsync
    "${RSYNC_FLAGS[@]}"
    "${RSYNC_EXTRA_ARGS[@]}"
    -e "ssh ${SSH_EXTRA_ARGS[*]}"
    --rsync-path="sudo rsync"
    "${SYNC_REMOTE_USER}@${SYNC_REMOTE_HOST}:${SOURCE_DIRECTORY}/"
    "${TARGET_DIRECTORY}/"
  )
  info "Using sudo on remote side for restricted files."
else
  RSYNC_CMD=(
    rsync
    "${RSYNC_FLAGS[@]}"
    "${RSYNC_EXTRA_ARGS[@]}"
    -e "ssh ${SSH_EXTRA_ARGS[*]}"
    "${SYNC_REMOTE_USER}@${SYNC_REMOTE_HOST}:${SOURCE_DIRECTORY}/"
    "${TARGET_DIRECTORY}/"
  )
fi

step "Running backup"
info "Command: ${RSYNC_CMD[*]}"
info "Source:  ${SYNC_REMOTE_USER}@${SYNC_REMOTE_HOST}:${SYNC_SSH_PORT}/${SOURCE_DIRECTORY}/"
info "Dest:    ${TARGET_DIRECTORY}/"
echo ""

if "${RSYNC_CMD[@]}"; then
  echo ""
  success "Backup complete!"
  info "Local backup: ${TARGET_DIRECTORY}/"
else
  error "rsync failed. See output above for details."
  exit 1
fi
