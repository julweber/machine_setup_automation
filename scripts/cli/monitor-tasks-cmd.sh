#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# monitor-tasks-cmd.sh — Implement the `spec monitor-tasks` subcommand.
#
# Usage (via bin/spec dispatcher):
#   spec monitor-tasks <feature-name>
#   spec monitor-tasks <feature-name> --print
#
# Wraps scripts/task-monitor.sh, resolving the tasks.yaml path from the
# feature name using the convention: tasks/<feature-name>/tasks.yaml
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MONITOR="${SCRIPT_DIR}/task-monitor.sh"

# ── Usage ─────────────────────────────────────────────────────────────────────

print_usage() {
    cat >&2 <<'EOF'
Usage: spec monitor-tasks <feature-name> [--print]

Monitor task progress for a feature.

Arguments:
  <feature-name>   Name of the feature (resolves to tasks/<feature-name>/tasks.yaml)

Options:
  --print          Print the task summary once and exit (non-interactive)
  --help           Show this help message and exit

Examples:
  spec monitor-tasks my-feature          # Live interactive dashboard
  spec monitor-tasks my-feature --print  # Print once and exit
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local feature_name=""
    local extra_args=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h)
                print_usage
                exit 0
                ;;
            --print)
                extra_args+=("--print")
                shift
                ;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                echo "" >&2
                print_usage
                exit 1
                ;;
            *)
                if [ -z "$feature_name" ]; then
                    feature_name="$1"
                else
                    echo "Error: Unexpected argument '$1'" >&2
                    echo "" >&2
                    print_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$feature_name" ]; then
        echo "Error: No feature name specified." >&2
        echo "" >&2
        print_usage
        exit 1
    fi

    local tasks_file="${PWD}/tasks/${feature_name}/tasks.yaml"

    if [ ! -f "$tasks_file" ]; then
        echo "Error: tasks.yaml not found for feature '${feature_name}'" >&2
        echo "       Expected: ${tasks_file}" >&2
        exit 1
    fi

    exec "$TASK_MONITOR" "${extra_args[@]}" "$tasks_file"
}

main "$@"
