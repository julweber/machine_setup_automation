#!/usr/bin/env bash

# task-monitor.sh - Monitor task progress from a YAML task file

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <path-to-tasks.yaml>

Monitor task progress from a YAML task file.

OPTIONS:
  --print       Print the task summary once to stdout and exit (non-interactive)
  --help        Show this help message and exit

ARGUMENTS:
  <path-to-tasks.yaml>
                Path to a YAML task file containing a "tasks" array where each
                task has at minimum an "id", "title", and "status" field.

INTERACTIVE MODE (default):
  The dashboard refreshes every 3 seconds.
  Press 'q' or Ctrl+C to quit.

EXAMPLES:
  $(basename "$0") tasks.yaml               # Live interactive dashboard
  $(basename "$0") --print tasks.yaml       # Print once and exit
  $(basename "$0") --help                   # Show this help

EXIT CODES:
  0   Success
  1   Missing or invalid arguments, missing dependency, or file not found
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────

PRINT_MODE=false
TASK_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --print)
            PRINT_MODE=true
            shift
            ;;
        -*)
            echo "Error: Unknown option: $1"
            echo "Run '$(basename "$0") --help' for usage."
            exit 1
            ;;
        *)
            if [[ -n "$TASK_FILE" ]]; then
                echo "Error: Unexpected argument: $1"
                echo "Run '$(basename "$0") --help' for usage."
                exit 1
            fi
            TASK_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$TASK_FILE" ]]; then
    echo "Error: No task file specified."
    echo "Run '$(basename "$0") --help' for usage."
    exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
    echo "Error: File not found: $TASK_FILE"
    exit 1
fi

if ! command -v yq &>/dev/null; then
    echo "Error: 'yq' is required but not installed. Please install yq."
    exit 1
fi

# ── Rendering ─────────────────────────────────────────────────────────────────

build_display() {
    # $1: "interactive" or "print" — controls whether clear + footer are shown
    local mode="${1:-interactive}"

    local yaml_content
    yaml_content=$(cat "$TASK_FILE")

    local total passed_count pending_count pct
    total=$(echo "$yaml_content" | yq '.tasks | length')
    passed_count=$(echo "$yaml_content" | yq '[.tasks[] | select(.status == "passed")] | length')
    pending_count=$(echo "$yaml_content" | yq '[.tasks[] | select(.status == "pending")] | length')

    if [[ $total -gt 0 ]]; then
        pct=$(echo "scale=1; $passed_count * 100 / $total" | bc)
    else
        pct="0.0"
    fi

    local passed_list pending_list
    passed_list=$(echo "$yaml_content" | yq -r '.tasks[] | select(.status == "passed") | "  [✓] \(.id): \(.title)"')
    pending_list=$(echo "$yaml_content" | yq -r '.tasks[] | select(.status == "pending") | "  [ ] \(.id): \(.title)"')

    # Progress bar
    local bar_width=40
    local filled empty bar
    filled=$(echo "$passed_count * $bar_width / $total" | bc 2>/dev/null || echo 0)
    empty=$((bar_width - filled))
    bar="["
    bar+=$(printf '%0.s█' $(seq 1 $filled) 2>/dev/null || true)
    bar+=$(printf '%0.s░' $(seq 1 $empty) 2>/dev/null || true)
    bar+="]"

    [[ "$mode" == "interactive" ]] && clear

    echo "╔══════════════════════════════════════════════════════════╗"
    printf  "║  📋  Task Monitor                                        ║\n"
    printf  "║  File: %-50s  ║\n" "$(basename "$TASK_FILE")"
    echo "╠══════════════════════════════════════════════════════════╣"
    printf  "║  Total Tasks : %-43s║\n" "$total"
    printf  "║  Passed      : %-43s║\n" "$passed_count"
    printf  "║  Pending     : %-43s║\n" "$pending_count"
    printf  "║  Completion  : %s %s%%%-$((41 - ${#pct} - bar_width))s║\n" "$bar" "$pct" ""
    echo "╠══════════════════════════════════════════════════════════╣"
    printf  "║  ✅  Passed Tasks (%d)%-38s║\n" "$passed_count" ""
    echo "╠══════════════════════════════════════════════════════════╣"
    if [[ -n "$passed_list" ]]; then
        while IFS= read -r line; do
            printf "║  %-56s║\n" "$line"
        done <<< "$passed_list"
    else
        printf "║  %-56s║\n" "(none)"
    fi
    echo "╠══════════════════════════════════════════════════════════╣"
    printf  "║  ⏳  Pending Tasks (%d)%-38s║\n" "$pending_count" ""
    echo "╠══════════════════════════════════════════════════════════╣"
    if [[ -n "$pending_list" ]]; then
        while IFS= read -r line; do
            printf "║  %-56s║\n" "$line"
        done <<< "$pending_list"
    else
        printf "║  %-56s║\n" "(none)"
    fi
    echo "╠══════════════════════════════════════════════════════════╣"
    if [[ "$mode" == "interactive" ]]; then
        printf  "║  Refreshes every 3s  │  Press 'q' or Ctrl+C to quit     ║\n"
    else
        printf  "║  Printed once (--print mode)                             ║\n"
    fi
    echo "╚══════════════════════════════════════════════════════════╝"
}

# ── Print mode ────────────────────────────────────────────────────────────────

if [[ "$PRINT_MODE" == true ]]; then
    build_display "print"
    exit 0
fi

# ── Interactive mode ──────────────────────────────────────────────────────────

tput civis 2>/dev/null || true
tput smcup 2>/dev/null || true

cleanup() {
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    echo ""
    echo "Exiting task monitor."
    exit 0
}
trap cleanup SIGINT SIGTERM

check_quit() {
    local key
    if read -r -s -n1 -t 0.1 key 2>/dev/null; then
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            cleanup
        fi
    fi
}

while true; do
    build_display "interactive"
    for _ in $(seq 1 30); do
        check_quit
    done
done