#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-review-cmd.sh — Implement the `spec review` subcommand
#
# Usage (via bin/spec dispatcher):
#   spec review [feature-name]
#
# If feature-name is omitted:
#   1. Try to detect it from the current git branch (feat/<name> pattern).
#   2. If no feat/ branch, list available features and prompt for selection.
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Usage ─────────────────────────────────────────────────────────────────────

print_usage() {
    cat >&2 <<'EOF'
Usage:
  spec review [feature-name]

Arguments:
  feature-name   Name of the feature to review (kebab-case).
                 If omitted, auto-detected from the current git branch
                 (feat/<name>) or selected interactively from available features.

Examples:
  spec review user-authentication
  spec review              # auto-detects or prompts for selection
EOF
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# detect_feature_from_branch: echo the feature name extracted from the current
# git branch (feat/<name> pattern), or empty string if not on a feature branch.
# Uses symbolic-ref to work correctly even in repos with no commits yet.
detect_feature_from_branch() {
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$branch" in
        feat/*)
            echo "${branch#feat/}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# list_features: echo the names of all features that have a spec directory under
# specification/features/, sorted alphabetically.
list_features() {
    local features_dir="${PWD}/specification/features"
    if [ ! -d "$features_dir" ]; then
        return
    fi
    # Only list directories (each one is a feature)
    find "$features_dir" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
        basename "$dir"
    done
}

# count_features: echo the number of feature directories.
count_features() {
    list_features | wc -l | tr -d ' '
}

# select_feature_interactively: display a numbered menu of features and read the
# user's selection. Echoes the chosen feature name, or exits 1 if no features
# are available or the selection is invalid.
select_feature_interactively() {
    local features=()
    mapfile -t features < <(list_features)

    if [ "${#features[@]}" -eq 0 ]; then
        echo "Error: No feature specs found under specification/features/." >&2
        echo "       Create a feature spec first:" >&2
        echo "         spec feature-brainstorm <feature-name>" >&2
        exit 1
    fi

    echo "" >&2
    echo "Available features:" >&2
    local i=1
    for feature in "${features[@]}"; do
        printf "  %d) %s\n" "$i" "$feature" >&2
        i=$((i + 1))
    done
    echo "" >&2
    printf "Select a feature (1-%d): " "${#features[@]}" >&2

    local choice
    read -r choice || choice=""

    if [ -z "$choice" ]; then
        echo "Error: No selection made." >&2
        exit 1
    fi

    # Validate it is a number in range
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#features[@]}" ]; then
        echo "Error: Invalid selection '${choice}'. Please enter a number between 1 and ${#features[@]}." >&2
        exit 1
    fi

    # Bash arrays are 0-indexed
    echo "${features[$((choice - 1))]}"
}

# validate_spec_exists: error and exit if the feature spec directory is missing
# or does not contain the required spec files (behaviors.md or tests.md).
validate_spec_exists() {
    local feature_name="$1"
    local spec_dir="${PWD}/specification/features/${feature_name}"

    if [ ! -d "$spec_dir" ]; then
        echo "Error: No spec found for feature '${feature_name}'." >&2
        echo "       Spec directory does not exist: ${spec_dir}" >&2
        echo "       Create a spec first:" >&2
        echo "         spec feature-brainstorm ${feature_name}" >&2
        exit 1
    fi

    # Check for the minimum required spec files
    local has_behaviors has_tests
    has_behaviors=0
    has_tests=0
    [ -f "${spec_dir}/behaviors.md" ] && has_behaviors=1
    [ -f "${spec_dir}/tests.md" ]     && has_tests=1

    if [ "$has_behaviors" -eq 0 ] || [ "$has_tests" -eq 0 ]; then
        echo "Error: Spec for '${feature_name}' is incomplete — missing required files." >&2
        [ "$has_behaviors" -eq 0 ] && echo "       Missing: ${spec_dir}/behaviors.md" >&2
        [ "$has_tests" -eq 0 ]     && echo "       Missing: ${spec_dir}/tests.md" >&2
        echo "" >&2
        echo "       Run brainstorm first to create the spec:" >&2
        echo "         spec feature-brainstorm ${feature_name}" >&2
        exit 1
    fi
}

# print_guidance: display the guidance block for the review step.
print_guidance() {
    local feature_name="$1"
    cat <<EOF

Run the following command in your AI agent session:

  /spec-review ${feature_name}

This will start an interactive spec review for '${feature_name}'.

EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local feature_name="${1:-}"

    if [ -n "$feature_name" ]; then
        # Explicit feature name provided — use it directly
        :
    else
        # Try to detect from current git branch
        feature_name="$(detect_feature_from_branch)"

        if [ -z "$feature_name" ]; then
            # No feature branch — prompt for interactive selection
            feature_name="$(select_feature_interactively)"
        fi
    fi

    # Validate the spec exists and has required files
    validate_spec_exists "$feature_name"

    # Print the guidance block
    print_guidance "$feature_name"
}

main "$@"
