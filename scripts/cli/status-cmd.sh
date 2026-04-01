#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-status-cmd.sh — Implement the `spec status` and `spec list-features`
# subcommands.
#
# Usage (via bin/spec dispatcher):
#   spec status [--json]
#   spec list-features [--status] [--json]
#
# Scans all features in specification/features/, reads tasks.yaml for progress,
# detects active git worktrees, and outputs a formatted table or JSON.
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Constants ──────────────────────────────────────────────────────────────────

# Progress bar width (number of characters)
BAR_WIDTH=10

# ── Color helpers ──────────────────────────────────────────────────────────────

# Only use colors when writing to a real terminal
if [ -t 1 ]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_CYAN="\033[36m"
    COLOR_RED="\033[31m"
    COLOR_DIM="\033[2m"
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_CYAN=""
    COLOR_RED=""
    COLOR_DIM=""
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

# list_features: echo the names of all features that have a spec directory under
# specification/features/, sorted alphabetically.
list_features() {
    local features_dir="${PWD}/specification/features"
    if [ ! -d "$features_dir" ]; then
        return
    fi
    find "$features_dir" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
        basename "$dir"
    done
}

# get_worktree_list: output the list of known worktree paths from git.
# Returns empty string if git is not available or this is not a git repo.
get_worktree_list() {
    git worktree list --porcelain 2>/dev/null | grep '^worktree ' | awk '{print $2}' || true
}

# project_name: attempt to derive the project name from the git remote or
# the current directory name.
project_name() {
    local name
    name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || basename "$PWD")"
    echo "$name"
}

# build_progress_bar: given passed count and total count, output a ░/█ bar.
# Arguments: <passed> <total>
build_progress_bar() {
    local passed="$1"
    local total="$2"
    local filled=0
    local empty="$BAR_WIDTH"

    if [ "$total" -gt 0 ]; then
        # Integer division: filled = (passed * BAR_WIDTH) / total
        filled=$(( (passed * BAR_WIDTH) / total ))
        empty=$(( BAR_WIDTH - filled ))
    fi

    local bar=""
    local i
    for (( i = 0; i < filled; i++ )); do
        bar="${bar}█"
    done
    for (( i = 0; i < empty; i++ )); do
        bar="${bar}░"
    done
    echo "$bar"
}

# compute_status: given passed, pending, failed counts, output a status label.
compute_status() {
    local passed="$1"
    local pending="$2"
    local failed="$3"
    local total=$(( passed + pending + failed ))

    if [ "$total" -eq 0 ]; then
        echo "no-tasks"
    elif [ "$failed" -gt 0 ]; then
        echo "failed"
    elif [ "$passed" -eq "$total" ]; then
        echo "complete"
    elif [ "$passed" -eq 0 ]; then
        echo "pending"
    else
        echo "in-progress"
    fi
}

# status_color: given a status string, output the corresponding ANSI color code.
status_color() {
    case "$1" in
        complete)    echo "$COLOR_GREEN" ;;
        in-progress) echo "$COLOR_CYAN" ;;
        failed)      echo "$COLOR_RED" ;;
        pending)     echo "$COLOR_YELLOW" ;;
        *)           echo "$COLOR_DIM" ;;
    esac
}

# read_tasks_yaml: given a tasks.yaml file path, use yq to parse it.
# Outputs: "<passed> <pending> <failed> <feature_name>" on success.
# On failure, prints a warning to stderr and returns 1.
read_tasks_yaml() {
    local yaml_file="$1"

    if ! yq --version > /dev/null 2>&1; then
        echo "Warning: yq is not installed; cannot parse tasks.yaml" >&2
        return 1
    fi

    local feature_name passed pending failed
    feature_name="$(yq '.featureName // ""' "$yaml_file" 2>/dev/null)" || {
        echo "Warning: Failed to parse YAML in ${yaml_file}" >&2
        return 1
    }

    # Validate that parsing actually succeeded (yq returns "null" on bad YAML)
    if [ "$feature_name" = "null" ] || [ -z "$feature_name" ]; then
        echo "Warning: Invalid or missing featureName in ${yaml_file}" >&2
        return 1
    fi

    passed="$(yq '[.tasks[] | select(.status == "passed")] | length' "$yaml_file" 2>/dev/null)" || {
        echo "Warning: Failed to count passed tasks in ${yaml_file}" >&2
        return 1
    }
    pending="$(yq '[.tasks[] | select(.status == "pending")] | length' "$yaml_file" 2>/dev/null)" || {
        echo "Warning: Failed to count pending tasks in ${yaml_file}" >&2
        return 1
    }
    failed="$(yq '[.tasks[] | select(.status == "failed")] | length' "$yaml_file" 2>/dev/null)" || {
        echo "Warning: Failed to count failed tasks in ${yaml_file}" >&2
        return 1
    }

    # Guard: yq may return "null" for empty arrays
    [ "$passed"  = "null" ] && passed=0
    [ "$pending" = "null" ] && pending=0
    [ "$failed"  = "null" ] && failed=0

    echo "$passed $pending $failed $feature_name"
}

# check_worktree: given project_name and feature_name, check if a git worktree
# exists at the conventional sibling path <project>-feat-<feature>.
# Prints "yes" if found, "no" otherwise.
check_worktree() {
    local proj_name="$1"
    local feature_name="$2"
    local project_root
    project_root="$(git rev-parse --show-toplevel 2>/dev/null)" || project_root="$PWD"
    local parent_dir
    parent_dir="$(dirname "$project_root")"
    local sibling_path="${parent_dir}/${proj_name}-feat-${feature_name}"

    # Check git's known worktrees
    if git worktree list --porcelain 2>/dev/null | grep -qF "worktree ${sibling_path}"; then
        echo "yes"
        return
    fi

    # Also check if the directory exists (worktree may be detached)
    if [ -d "$sibling_path" ]; then
        echo "yes"
        return
    fi

    echo "no"
}

# get_feature_branch: given project root and feature name, return the branch
# name if a feat/<feature> branch exists, or "-" if not.
get_feature_branch() {
    local feature_name="$1"
    if git show-ref --verify --quiet "refs/heads/feat/${feature_name}" 2>/dev/null; then
        echo "feat/${feature_name}"
    elif git show-ref --verify --quiet "refs/remotes/origin/feat/${feature_name}" 2>/dev/null; then
        echo "feat/${feature_name}"
    else
        echo "-"
    fi
}

# ── Output: Table Format ───────────────────────────────────────────────────────

print_table() {
    local features=()
    mapfile -t features < <(list_features)

    local proj_name
    proj_name="$(project_name)"

    if [ "${#features[@]}" -eq 0 ]; then
        echo ""
        echo "No features found under specification/features/."
        echo ""
        echo "Get started by creating a feature spec:"
        echo "  spec new-feature"
        echo "  spec feature-brainstorm <feature-name>"
        echo ""
        return 0
    fi

    # Header
    echo ""
    printf "${COLOR_BOLD}%-28s %-12s %-14s %-24s %-8s${COLOR_RESET}\n" \
        "Feature" "Status" "Progress" "Branch" "Worktree"
    printf '%s\n' "$(printf '─%.0s' {1..90})"

    local feature
    for feature in "${features[@]}"; do
        local yaml_file="${PWD}/tasks/${feature}/tasks.yaml"
        local passed=0 pending=0 failed=0 total=0
        local status_label bar pct worktree_sym branch col

        if [ -f "$yaml_file" ]; then
            local parsed
            if parsed="$(read_tasks_yaml "$yaml_file" 2>/tmp/spec-status-stderr)"; then
                read -r passed pending failed _ <<< "$parsed"
            else
                # Warn on stderr and skip this feature
                cat /tmp/spec-status-stderr >&2
                printf "Warning: skipping feature '%s' — could not parse tasks.yaml\n" "$feature" >&2
                continue
            fi
        else
            # No tasks.yaml yet → treat as no tasks
            passed=0
            pending=0
            failed=0
        fi

        total=$(( passed + pending + failed ))
        status_label="$(compute_status "$passed" "$pending" "$failed")"
        bar="$(build_progress_bar "$passed" "$total")"

        if [ "$total" -gt 0 ]; then
            # Use awk for floating point percentage
            pct="$(awk "BEGIN { printf \"%.0f%%\", ($passed/$total)*100 }")"
        else
            pct="0%"
        fi

        # Worktree detection
        if check_worktree "$proj_name" "$feature" | grep -q "^yes$"; then
            worktree_sym="✓"
        else
            worktree_sym="✗"
        fi

        branch="$(get_feature_branch "$feature")"
        # Truncate branch to fit column
        if [ "${#branch}" -gt 22 ]; then
            branch="${branch:0:19}..."
        fi

        col="$(status_color "$status_label")"

        printf "${col}%-28s %-12s${COLOR_RESET} %s %-3s  ${COLOR_DIM}%-24s${COLOR_RESET}  %s\n" \
            "$feature" "$status_label" "$bar" "$pct" "$branch" "$worktree_sym"
    done

    printf '%s\n' "$(printf '─%.0s' {1..90})"
    echo ""
}

# ── Output: JSON Format ────────────────────────────────────────────────────────

print_json() {
    local features=()
    mapfile -t features < <(list_features)

    local proj_name
    proj_name="$(project_name)"

    # Build the JSON features array
    local first=1
    printf '{\n'
    printf '  "project": %s,\n' "$(printf '%s' "$proj_name" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
    printf '  "features": [\n'

    local feature
    for feature in "${features[@]}"; do
        local yaml_file="${PWD}/tasks/${feature}/tasks.yaml"
        local passed=0 pending=0 failed=0 total=0 progress_pct=0

        if [ -f "$yaml_file" ]; then
            local parsed
            if parsed="$(read_tasks_yaml "$yaml_file" 2>/tmp/spec-status-stderr)"; then
                read -r passed pending failed _ <<< "$parsed"
            else
                cat /tmp/spec-status-stderr >&2
                printf "Warning: skipping feature '%s' — could not parse tasks.yaml\n" "$feature" >&2
                continue
            fi
        fi

        total=$(( passed + pending + failed ))
        if [ "$total" -gt 0 ]; then
            progress_pct="$(awk "BEGIN { printf \"%.1f\", ($passed/$total)*100 }")"
        else
            progress_pct="0.0"
        fi

        local status_label
        status_label="$(compute_status "$passed" "$pending" "$failed")"

        local branch
        branch="$(get_feature_branch "$feature")"

        local has_worktree
        has_worktree="$(check_worktree "$proj_name" "$feature")"
        local worktree_active="false"
        [ "$has_worktree" = "yes" ] && worktree_active="true"

        if [ "$first" -eq 0 ]; then
            printf ',\n'
        fi
        first=0

        local feature_json
        feature_json="$(printf '%s' "$feature" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
        local branch_json
        branch_json="$(printf '%s' "$branch" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"

        printf '    {\n'
        printf '      "featureName": %s,\n' "$feature_json"
        printf '      "status": "%s",\n' "$status_label"
        printf '      "total_tasks": %d,\n' "$total"
        printf '      "passed": %d,\n' "$passed"
        printf '      "pending": %d,\n' "$pending"
        printf '      "failed": %d,\n' "$failed"
        printf '      "progress_percent": %s,\n' "$progress_pct"
        printf '      "branch": %s,\n' "$branch_json"
        printf '      "worktree_active": %s\n' "$worktree_active"
        printf '    }'
    done

    printf '\n  ]\n'
    printf '}\n'
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    # First argument may be "list-features" (passed by bin/spec for list-features subcommand)
    if [ "${1:-}" = "list-features" ]; then
        shift
    fi

    # Parse flags
    local json_mode=0
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --json)
                json_mode=1
                shift
                ;;
            --status)
                # list-features --status is equivalent to spec status
                shift
                ;;
            --help|-h)
                cat >&2 <<'EOF'
Usage:
  spec status [--json]
  spec list-features [--status] [--json]

Flags:
  --json    Output structured JSON instead of a formatted table

Examples:
  spec status
  spec status --json
  spec list-features
EOF
                exit 0
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    if [ "$json_mode" -eq 1 ]; then
        print_json
    else
        print_table
    fi
}

main "$@"
