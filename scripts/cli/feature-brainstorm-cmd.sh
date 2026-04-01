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

# is_kebab_case: return 0 if the name contains only lowercase letters, digits,
# and hyphens, and does not start or end with a hyphen.
is_kebab_case() {
    local name="$1"
    # Must be non-empty, only [a-z0-9-], not start/end with '-'
    if [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [[ "$name" =~ ^[a-z0-9]$ ]]; then
        return 0
    fi
    return 1
}

# validate_kebab: print an error and exit 1 if name is not valid kebab-case.
validate_kebab() {
    local name="$1"
    if ! is_kebab_case "$name"; then
        echo "Error: Invalid feature name '${name}'." >&2
        echo "       Feature names must be kebab-case (lowercase letters, digits, and hyphens)." >&2
        echo "       Example: user-authentication" >&2
        exit 1
    fi
}

# validate_project: ensure specification/project/ exists with at least one .md file.
validate_project() {
    local spec_project_dir="${PWD}/specification/project"
    if [ ! -d "$spec_project_dir" ]; then
        echo "Error: No project specs found. '${spec_project_dir}' does not exist." >&2
        echo "       Initialize this project first:" >&2
        echo "         spec init <project-name>" >&2
        exit 1
    fi

    local md_count
    md_count="$(find "$spec_project_dir" -maxdepth 1 -name '*.md' | wc -l)"
    if [ "$md_count" -eq 0 ]; then
        echo "Error: No project spec files found in '${spec_project_dir}'." >&2
        echo "       Initialize this project first:" >&2
        echo "         spec init <project-name>" >&2
        exit 1
    fi
}

# check_existing_spec: if the feature spec directory already exists, warn and
# offer the user the option to cancel (pressing anything other than 'y'/'Y'
# or just hitting Enter = cancel).
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
        printf "Overwrite existing spec? [y/N] " >&2
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
