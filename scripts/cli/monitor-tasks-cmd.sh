#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-monitor-tasks-cmd.sh — Implement the `spec monitor-tasks` subcommand.
#
# Usage (via bin/spec dispatcher):
#   spec monitor-tasks --json <path-to-tasks.yaml>
#
# Parses the given tasks.yaml file using yq, calculates progress metrics, and
# outputs valid JSON matching the stable schema:
#   {
#     "file": "...",
#     "featureName": "...",
#     "total_tasks": <n>,
#     "passed": <n>,
#     "pending": <n>,
#     "failed": <n>,
#     "progress_percent": <float>,
#     "tasks": [{"id": "...", "title": "...", "status": "..."}, ...]
#   }
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Usage ──────────────────────────────────────────────────────────────────────

print_usage() {
    cat >&2 <<'EOF'
Usage: spec monitor-tasks --json <path-to-tasks.yaml>

Parses a tasks.yaml file and outputs a JSON progress summary.

Options:
  --json <path>   Path to the tasks.yaml file (required)

Output schema:
  {
    "file": "<path>",
    "featureName": "<name>",
    "total_tasks": <number>,
    "passed": <number>,
    "pending": <number>,
    "failed": <number>,
    "progress_percent": <float>,
    "tasks": [{"id": "...", "title": "...", "status": "..."}, ...]
  }

Exit codes:
  0   Success — valid JSON output on stdout
  1   File not found or invalid YAML
EOF
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# json_string: JSON-encode an arbitrary string using python3.
json_string() {
    printf '%s' "$1" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'
}

# check_yq: verify yq is available, exit 1 with guidance if not.
check_yq() {
    if ! yq --version > /dev/null 2>&1; then
        echo "Error: yq is required but not installed." >&2
        echo "  Install it from: https://github.com/mikefarah/yq" >&2
        exit 1
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local yaml_file=""
    local json_mode=0

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --json)
                json_mode=1
                shift
                if [ $# -gt 0 ] && [ "${1:0:1}" != "-" ]; then
                    yaml_file="$1"
                    shift
                fi
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                echo "" >&2
                print_usage
                exit 1
                ;;
            *)
                # Positional argument: treat as the yaml file if we don't have one yet
                if [ -z "$yaml_file" ]; then
                    yaml_file="$1"
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

    # Require --json mode (only supported mode right now)
    if [ "$json_mode" -eq 0 ]; then
        echo "Error: spec monitor-tasks requires the --json flag." >&2
        echo "" >&2
        print_usage
        exit 1
    fi

    # Require a yaml file path
    if [ -z "$yaml_file" ]; then
        echo "Error: Missing path to tasks.yaml file." >&2
        echo "  Usage: spec monitor-tasks --json <path-to-tasks.yaml>" >&2
        exit 1
    fi

    # ── Validate file existence ────────────────────────────────────────────────

    if [ ! -e "$yaml_file" ]; then
        echo "Error: File not found: ${yaml_file}" >&2
        echo "  The specified tasks.yaml file does not exist." >&2
        exit 1
    fi

    if [ ! -f "$yaml_file" ]; then
        echo "Error: Path is not a regular file: ${yaml_file}" >&2
        exit 1
    fi

    # ── Check yq availability ─────────────────────────────────────────────────

    check_yq

    # ── Parse YAML ────────────────────────────────────────────────────────────

    # Attempt to extract featureName first as a basic YAML validity check.
    local feature_name
    local yq_err_file
    yq_err_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$yq_err_file'" EXIT

    if ! feature_name="$(yq '.featureName // ""' "$yaml_file" 2>"$yq_err_file" | sed 's/^"//;s/"$//')"; then
        local yq_err
        yq_err="$(cat "$yq_err_file")"
        echo "Error: Failed to parse YAML in: ${yaml_file}" >&2
        if [ -n "$yq_err" ]; then
            echo "  Parse error: ${yq_err}" >&2
        fi
        echo "  Please check the file for YAML syntax errors (e.g., unclosed brackets, bad indentation)." >&2
        exit 1
    fi

    # yq may return "null" or empty string for a missing/invalid featureName
    if [ "$feature_name" = "null" ] || [ -z "$feature_name" ]; then
        # Try to still read any tasks — featureName may just be absent
        feature_name=""
    fi

    # Check if the tasks key is parseable (catches structurally invalid YAML)
    local tasks_check
    if ! tasks_check="$(yq '.tasks // []' "$yaml_file" 2>"$yq_err_file")"; then
        local yq_err
        yq_err="$(cat "$yq_err_file")"
        echo "Error: Invalid YAML structure in: ${yaml_file}" >&2
        if [ -n "$yq_err" ]; then
            # Try to extract a line number from the error
            local line_info
            line_info="$(echo "$yq_err" | grep -oE 'line [0-9]+' | head -1 || true)"
            if [ -n "$line_info" ]; then
                echo "  Parse error at ${line_info}: ${yq_err}" >&2
            else
                echo "  Parse error: ${yq_err}" >&2
            fi
        fi
        echo "  Please fix the YAML syntax errors and try again." >&2
        exit 1
    fi

    # Validate the tasks field is actually a sequence (not "null" or scalar)
    if [ "$tasks_check" = "null" ]; then
        echo "Error: Invalid YAML — 'tasks' field is null or missing in: ${yaml_file}" >&2
        echo "  Please fix the YAML syntax errors and try again." >&2
        exit 1
    fi

    # ── Count task statuses ───────────────────────────────────────────────────

    local passed pending failed
    passed="$(yq '[.tasks[] | select(.status == "passed")] | length' "$yaml_file" 2>/dev/null)" || passed=0
    pending="$(yq '[.tasks[] | select(.status == "pending")] | length' "$yaml_file" 2>/dev/null)" || pending=0
    failed="$(yq '[.tasks[] | select(.status == "failed")] | length' "$yaml_file" 2>/dev/null)" || failed=0

    # Guard: yq may return "null" for empty arrays
    [ "$passed"  = "null" ] && passed=0
    [ "$pending" = "null" ] && pending=0
    [ "$failed"  = "null" ] && failed=0

    local total=$(( passed + pending + failed ))

    # ── Calculate progress_percent ────────────────────────────────────────────

    local progress_percent
    if [ "$total" -gt 0 ]; then
        progress_percent="$(awk "BEGIN { printf \"%.1f\", ($passed / $total) * 100 }")"
    else
        progress_percent="0.0"
    fi

    # ── Build tasks array ─────────────────────────────────────────────────────

    # Extract task count for iteration
    local task_count
    task_count="$(yq '.tasks | length' "$yaml_file" 2>/dev/null)" || task_count=0
    [ "$task_count" = "null" ] && task_count=0

    # ── Output JSON ───────────────────────────────────────────────────────────

    local file_json feature_json
    file_json="$(json_string "$yaml_file")"
    feature_json="$(json_string "$feature_name")"

    printf '{\n'
    printf '  "file": %s,\n'             "$file_json"
    printf '  "featureName": %s,\n'      "$feature_json"
    printf '  "total_tasks": %d,\n'      "$total"
    printf '  "passed": %d,\n'           "$passed"
    printf '  "pending": %d,\n'          "$pending"
    printf '  "failed": %d,\n'           "$failed"
    printf '  "progress_percent": %s,\n' "$progress_percent"
    printf '  "tasks": [\n'

    # Emit one JSON object per task
    local i first_task=1
    for (( i = 0; i < task_count; i++ )); do
        local task_id task_title task_status
        task_id="$(yq ".tasks[${i}].id // \"\"" "$yaml_file" 2>/dev/null | sed 's/^"//;s/"$//')" || task_id=""
        task_title="$(yq ".tasks[${i}].title // \"\"" "$yaml_file" 2>/dev/null | sed 's/^"//;s/"$//')" || task_title=""
        task_status="$(yq ".tasks[${i}].status // \"\"" "$yaml_file" 2>/dev/null | sed 's/^"//;s/"$//')" || task_status=""

        # Skip null entries
        [ "$task_id"     = "null" ] && task_id=""
        [ "$task_title"  = "null" ] && task_title=""
        [ "$task_status" = "null" ] && task_status=""

        local id_json title_json status_json
        id_json="$(json_string "$task_id")"
        title_json="$(json_string "$task_title")"
        status_json="$(json_string "$task_status")"

        if [ "$first_task" -eq 0 ]; then
            printf ',\n'
        fi
        first_task=0

        printf '    {"id": %s, "title": %s, "status": %s}' \
            "$id_json" "$title_json" "$status_json"
    done

    if [ "$task_count" -gt 0 ]; then
        printf '\n'
    fi

    printf '  ]\n'
    printf '}\n'
}

main "$@"
