#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-feature-brainstorm-cmd.sh — Implement the `spec feature-brainstorm` subcommand
#
# Usage (via bin/spec dispatcher):
#   spec feature-brainstorm [feature-name]
#
# If feature-name is omitted the user is prompted interactively.
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

# ── Usage ─────────────────────────────────────────────────────────────────────

print_usage() {
    cat >&2 <<'EOF'
Usage:
  spec feature-brainstorm [feature-name]

Arguments:
  feature-name   Name of the feature (kebab-case, e.g. user-authentication).
                 If omitted you will be prompted interactively.

Examples:
  spec feature-brainstorm user-authentication
  spec feature-brainstorm              # prompts for name
EOF
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# check_existing_spec: if the feature spec directory already exists, warn and
# offer the user the option to cancel.
check_existing_spec() {
    local feature_name="$1"
    local spec_dir="${PWD}/specification/features/${feature_name}"

    if [ -d "$spec_dir" ]; then
        echo ""
        echo "Warning: A spec directory already exists for '${feature_name}':" >&2
        echo "  ${spec_dir}" >&2
        # List existing files
        local files=()
        mapfile -t files < <(find "$spec_dir" -maxdepth 1 -type f | sort)
        if [ "${#files[@]}" -gt 0 ]; then
            echo "  Existing files:" >&2
            for f in "${files[@]}"; do
                echo "    - $(basename "$f")" >&2
            done
        fi
        echo "" >&2
        confirm_overwrite "spec" "$spec_dir"
    fi
}

# print_guidance: display the guidance block telling the user which command to
# run in their AI agent session.
print_guidance() {
    local feature_name="$1"
    cat <<EOF

Run the following command in your AI agent session:

  /spec-feature-brainstorm ${feature_name}

This will guide you through creating:
  - specification/features/${feature_name}/behaviors.md
  - specification/features/${feature_name}/tests.md

EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local feature_name="${1:-}"

    # If feature name is omitted, prompt interactively
    if [ -z "$feature_name" ]; then
        printf "Enter feature name (kebab-case): "
        read -r feature_name || feature_name=""
        if [ -z "$feature_name" ]; then
            echo "Error: Feature name cannot be empty." >&2
            print_usage
            exit 1
        fi
    fi

    # Validate kebab-case format
    validate_kebab "$feature_name"

    # Validate project is initialized
    validate_project

    # Check for existing spec directory
    check_existing_spec "$feature_name"

    # Print the guidance block
    print_guidance "$feature_name"
}

main "$@"
