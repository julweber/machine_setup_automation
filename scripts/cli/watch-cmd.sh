#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# watch-cmd.sh — Implement the `spec watch` subcommand
#
# Lists running ralph-* tmux sessions and attaches to one.
# ──────────────────────────────────────────────────────────────────────────────

set -e

LIB_SH="${BASH_SOURCE[0]%/*}/lib.sh"
if [ ! -f "$LIB_SH" ]; then
    echo "Error: Shared CLI library not found at '${LIB_SH}'." >&2
    echo "       Restore scripts/cli/lib.sh or refresh the framework with: spec init --update" >&2
    exit 1
fi
# shellcheck disable=SC1090,SC1091
source "$LIB_SH"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat >&2 <<'EOF'
Usage: spec watch [feature-name] [--list]

Attaches to a running Ralph tmux session (ralph-<feature-name>).

Arguments:
  feature-name   Name of the feature (optional). If omitted and exactly one
                 ralph session is running, attaches to it automatically.
                 If multiple sessions are running, prompts you to choose.

Options:
  --list         Print all running Ralph sessions and exit.
EOF
    exit 0
fi

if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is not installed." >&2
    exit 1
fi

LIST=false
FEATURE_NAME=""
for arg in "$@"; do
    case "$arg" in
        --list) LIST=true ;;
        *) FEATURE_NAME="$arg" ;;
    esac
done

if [ "$LIST" = true ]; then
    mapfile -t sessions < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^ralph-' || true)
    if [ ${#sessions[@]} -eq 0 ]; then
        echo "No running Ralph sessions."
    else
        for s in "${sessions[@]}"; do
            echo "$s"
        done
    fi
    exit 0
fi

if [ -n "$FEATURE_NAME" ]; then
    session="ralph-${FEATURE_NAME}"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "Error: no tmux session found for feature '${FEATURE_NAME}' (looked for '${session}')." >&2
        exit 1
    fi
    exec tmux attach -t "$session"
fi

# No feature name given — find all ralph-* sessions
mapfile -t sessions < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^ralph-' || true)

if [ ${#sessions[@]} -eq 0 ]; then
    echo "No running Ralph sessions found." >&2
    exit 1
fi

if [ ${#sessions[@]} -eq 1 ]; then
    exec tmux attach -t "${sessions[0]}"
fi

# Multiple sessions — let the user pick
echo "Multiple Ralph sessions are running:"
echo ""
for i in "${!sessions[@]}"; do
    echo "  $((i+1))) ${sessions[$i]}"
done
echo ""
printf "Attach to [1-%d]: " "${#sessions[@]}"
read -r choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#sessions[@]}" ]; then
    echo "Invalid choice." >&2
    exit 1
fi

exec tmux attach -t "${sessions[$((choice-1))]}"
