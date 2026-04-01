#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-generate-tasks-cmd.sh — Implement the `spec generate-tasks` subcommand
#
# Usage (via bin/spec dispatcher):
#   spec generate-tasks [feature-name]
#
# If feature-name is omitted, auto-detects from the current git branch
# (feat/<name> pattern). Validates that the spec is reviewed (non-empty
# behaviors.md and tests.md exist). If tasks/<feature-name>/tasks.yaml already
# exists, warns and offers to cancel. On success, prints the guidance block.
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Usage ─────────────────────────────────────────────────────────────────────

print_usage() {
    cat >&2 <<'EOF'
Usage:
  spec generate-tasks [feature-name]

Arguments:
  feature-name   Name of the feature (kebab-case).
                 If omitted, auto-detected from the current git branch
                 (feat/<name> pattern).

Examples:
  spec generate-tasks user-authentication
  spec generate-tasks          # auto-detects from git branch
EOF
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# detect_feature_from_branch: echo the feature name extracted from the current
# git branch (feat/<name> pattern), or empty string if not on a feature branch.
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

# list_features: echo the names of all features with a spec directory, sorted.
list_features() {
    local features_dir="${PWD}/specification/features"
    if [ ! -d "$features_dir" ]; then
        return
    fi
    find "$features_dir" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
        basename "$dir"
    done
}

# validate_spec_reviewed: error and exit if behaviors.md or tests.md are missing
# or empty for the given feature.
validate_spec_reviewed() {
    local feature_name="$1"
    local spec_dir="${PWD}/specification/features/${feature_name}"

    if [ ! -d "$spec_dir" ]; then
        echo "Error: No spec found for feature '${feature_name}'." >&2
        echo "       Spec directory does not exist: ${spec_dir}" >&2
        echo "" >&2
        echo "       Create and review the spec first:" >&2
        echo "         spec feature-brainstorm ${feature_name}" >&2
        echo "         spec review ${feature_name}" >&2
        exit 1
    fi

    local behaviors_md="${spec_dir}/behaviors.md"
    local tests_md="${spec_dir}/tests.md"
    local missing_or_empty=0

    # Check behaviors.md: must exist and be non-empty
    if [ ! -f "$behaviors_md" ]; then
        echo "Error: Missing spec file: ${behaviors_md}" >&2
        missing_or_empty=1
    elif [ ! -s "$behaviors_md" ]; then
        echo "Error: Spec file is empty: ${behaviors_md}" >&2
        missing_or_empty=1
    fi

    # Check tests.md: must exist and be non-empty
    if [ ! -f "$tests_md" ]; then
        echo "Error: Missing spec file: ${tests_md}" >&2
        missing_or_empty=1
    elif [ ! -s "$tests_md" ]; then
        echo "Error: Spec file is empty: ${tests_md}" >&2
        missing_or_empty=1
    fi

    if [ "$missing_or_empty" -ne 0 ]; then
        echo "" >&2
        echo "       The spec for '${feature_name}' is incomplete or not yet reviewed." >&2
        echo "       Run the review step first:" >&2
        echo "         spec review ${feature_name}" >&2
        exit 1
    fi
}

# check_existing_tasks: if tasks/<feature>/tasks.yaml already exists, warn and
# offer the user the option to cancel (anything other than 'y'/'Y' = cancel).
check_existing_tasks() {
    local feature_name="$1"
    local tasks_file="${PWD}/tasks/${feature_name}/tasks.yaml"

    if [ -f "$tasks_file" ]; then
        echo "" >&2
        echo "Warning: tasks.yaml already exists for '${feature_name}':" >&2
        echo "  ${tasks_file}" >&2
        echo "" >&2
        printf "Overwrite existing tasks.yaml? [y/N] " >&2
        local answer
        read -r answer || answer="n"
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            echo "Cancelled." >&2
            exit 0
        fi
    fi
}

# print_guidance: display the guidance block telling the user which command to
# run in their AI agent session.
print_guidance() {
    local feature_name="$1"
    cat <<EOF

Run the following command in your AI agent session:

  /spec-to-tasks ${feature_name}

This will generate tasks/${feature_name}/tasks.yaml from your spec.

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
            # No feature branch — list available features and error with guidance
            echo "Error: No feature name provided and could not detect one from the current git branch." >&2
            echo "" >&2

            local features=()
            mapfile -t features < <(list_features)

            if [ "${#features[@]}" -gt 0 ]; then
                echo "Available features:" >&2
                for feature in "${features[@]}"; do
                    echo "  - ${feature}" >&2
                done
                echo "" >&2
                echo "Usage: spec generate-tasks <feature-name>" >&2
            else
                echo "No feature specs found under specification/features/." >&2
                echo "Create a feature spec first:" >&2
                echo "  spec feature-brainstorm <feature-name>" >&2
            fi
            exit 1
        fi
    fi

    # Validate the spec is reviewed (non-empty behaviors.md and tests.md)
    validate_spec_reviewed "$feature_name"

    # Check for existing tasks.yaml and offer to cancel
    check_existing_tasks "$feature_name"

    # Print the guidance block
    print_guidance "$feature_name"
}

main "$@"
