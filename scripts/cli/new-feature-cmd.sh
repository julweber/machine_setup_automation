#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-new-feature-cmd.sh — Implement the `spec new-feature` interactive wizard
#
# Usage (via bin/spec dispatcher):
#   spec new-feature [feature-name]
#
# Guides the user through the full feature creation workflow:
#   1. Feature name (kebab-case)
#   2. Brainstorm or review step
#   3. Generate tasks step
#   4. Implement step (with optional --agent / --max-iterations collection)
#
# Cancellation at any step exits cleanly with no partial files created.
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Helpers ───────────────────────────────────────────────────────────────────

# is_kebab_case: return 0 if name is valid kebab-case, 1 otherwise.
is_kebab_case() {
    local name="$1"
    if [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [[ "$name" =~ ^[a-z0-9]$ ]]; then
        return 0
    fi
    return 1
}

# validate_project: ensure specification/project/ exists with at least one .md file.
# Exits 1 with guidance if the project is not initialized.
validate_project() {
    local spec_project_dir="${PWD}/specification/project"
    if [ ! -d "$spec_project_dir" ]; then
        echo "Error: Project not initialized. '${spec_project_dir}' does not exist." >&2
        echo "" >&2
        echo "       Initialize the project first:" >&2
        echo "         spec init <project-name>" >&2
        exit 1
    fi

    local md_count
    md_count="$(find "$spec_project_dir" -maxdepth 1 -name '*.md' | wc -l)"
    if [ "$md_count" -eq 0 ]; then
        echo "Error: Project not initialized. No spec files in '${spec_project_dir}'." >&2
        echo "" >&2
        echo "       Initialize the project first:" >&2
        echo "         spec init <project-name>" >&2
        exit 1
    fi
}

# prompt_feature_name: prompt for a kebab-case feature name, looping on invalid
# input until the user provides a valid name or cancels (empty + EOF).
prompt_feature_name() {
    local name=""
    while true; do
        printf "Enter feature name (kebab-case): " >&2
        read -r name || name=""

        if [ -z "$name" ]; then
            echo "Cancelled." >&2
            exit 0
        fi

        if is_kebab_case "$name"; then
            echo "$name"
            return 0
        else
            echo "Error: Invalid feature name '${name}'." >&2
            echo "       Feature names must be kebab-case (lowercase letters, digits, and hyphens)." >&2
            echo "       Example: user-authentication" >&2
        fi
    done
}

# spec_exists: return 0 if specification/features/<feature> has behaviors.md or tests.md.
spec_exists() {
    local feature_name="$1"
    local spec_dir="${PWD}/specification/features/${feature_name}"
    [ -f "${spec_dir}/behaviors.md" ] || [ -f "${spec_dir}/tests.md" ]
}

# print_brainstorm_guidance: display agent session instructions for brainstorm step.
print_brainstorm_guidance() {
    local feature_name="$1"
    cat >&2 <<EOF

─── Step 1: Brainstorm ──────────────────────────────────────────────────────

Run the following command in your AI agent session to create the feature spec:

  /spec-feature-brainstorm ${feature_name}

This will guide you through creating:
  specification/features/${feature_name}/behaviors.md
  specification/features/${feature_name}/tests.md

─────────────────────────────────────────────────────────────────────────────
EOF
}

# print_review_guidance: display agent session instructions for review step.
print_review_guidance() {
    local feature_name="$1"
    cat >&2 <<EOF

─── Step: Review Spec ───────────────────────────────────────────────────────

Run the following command in your AI agent session to review the feature spec:

  /spec-review ${feature_name}

─────────────────────────────────────────────────────────────────────────────
EOF
}

# print_generate_tasks_guidance: display agent session instructions for task gen.
print_generate_tasks_guidance() {
    local feature_name="$1"
    cat >&2 <<EOF

─── Step 2: Generate Tasks ──────────────────────────────────────────────────

Once your spec is reviewed and ready, run the following command in your AI
agent session to generate the task list:

  /spec-to-tasks ${feature_name}

This will create: tasks/${feature_name}/tasks.yaml

─────────────────────────────────────────────────────────────────────────────
EOF
}

# confirm: prompt a yes/no question on stderr; return 0 for yes, 1 for no.
# Usage: confirm "Continue to generate tasks?"
confirm() {
    local prompt="$1"
    local answer
    printf "%s [y/N] " "$prompt" >&2
    read -r answer || answer="n"
    case "$answer" in
        y|Y) return 0 ;;
        *)   return 1 ;;
    esac
}

# ── Wizard steps ──────────────────────────────────────────────────────────────

# step_brainstorm_or_review: handle the spec creation/review step.
# When a spec already exists, offer a numbered menu. Otherwise guide to brainstorm.
step_brainstorm_or_review() {
    local feature_name="$1"

    if spec_exists "$feature_name"; then
        # Spec already exists — offer a numbered menu
        echo "" >&2
        echo "A spec already exists for '${feature_name}':" >&2
        echo "" >&2
        echo "  1) Review existing spec" >&2
        echo "  2) Re-brainstorm (overwrite existing spec)" >&2
        echo "  3) Cancel" >&2
        echo "" >&2
        printf "Choose an option (1-3): " >&2

        local choice
        read -r choice || choice="3"

        case "${choice:-3}" in
            1)
                print_review_guidance "$feature_name"
                ;;
            2)
                print_brainstorm_guidance "$feature_name"
                ;;
            3|*)
                echo "Cancelled." >&2
                exit 0
                ;;
        esac
    else
        # No spec yet — guide to brainstorm
        print_brainstorm_guidance "$feature_name"
    fi
}

# step_generate_tasks: offer to proceed to generate tasks.
step_generate_tasks() {
    local feature_name="$1"

    echo "" >&2
    if ! confirm "Proceed to generate tasks for '${feature_name}'?"; then
        echo "" >&2
        echo "You can generate tasks later by running:" >&2
        echo "  spec generate-tasks ${feature_name}" >&2
        exit 0
    fi

    print_generate_tasks_guidance "$feature_name"
}

# step_implement: offer to proceed to implementation with optional options.
step_implement() {
    local feature_name="$1"

    echo "" >&2
    if ! confirm "Proceed to launch implementation for '${feature_name}'?"; then
        echo "" >&2
        echo "You can launch implementation later by running:" >&2
        echo "  spec implement ${feature_name}" >&2
        exit 0
    fi

    # Collect agent preference
    local agent="opencode"
    echo "" >&2
    printf "Agent to use (opencode/claude/pi) [opencode]: " >&2
    local agent_input
    read -r agent_input || agent_input=""
    if [ -n "$agent_input" ]; then
        case "$agent_input" in
            opencode|claude|pi)
                agent="$agent_input"
                ;;
            *)
                echo "Warning: Invalid agent '${agent_input}', using default 'opencode'." >&2
                ;;
        esac
    fi

    # Collect max-iterations preference
    local max_iterations="5"
    printf "Max iterations [5]: " >&2
    local iter_input
    read -r iter_input || iter_input=""
    if [ -n "$iter_input" ]; then
        if [[ "$iter_input" =~ ^[0-9]+$ ]] && [ "$iter_input" -gt 0 ]; then
            max_iterations="$iter_input"
        else
            echo "Warning: Invalid max-iterations '${iter_input}', using default '5'." >&2
        fi
    fi

    echo "" >&2
    echo "─── Step 3: Implement ───────────────────────────────────────────────────────" >&2
    echo "" >&2
    echo "Launching implementation with the following configuration:" >&2
    echo "  Feature:        ${feature_name}" >&2
    echo "  Agent:          ${agent}" >&2
    echo "  Max iterations: ${max_iterations}" >&2
    echo "" >&2
    echo "─────────────────────────────────────────────────────────────────────────────" >&2
    echo "" >&2

    # Resolve path to spec CLI
    local spec_cli
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    spec_cli="${script_dir}/../bin/spec"

    exec "$spec_cli" implement "$feature_name" \
        --agent "$agent" \
        --max-iterations "$max_iterations"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local feature_name="${1:-}"

    # Step 0: Validate the project is initialized before showing any wizard prompts
    validate_project

    # Step 1: Determine the feature name
    if [ -z "$feature_name" ]; then
        feature_name="$(prompt_feature_name)"
        # prompt_feature_name exits cleanly if the user cancels
    else
        if ! is_kebab_case "$feature_name"; then
            echo "Error: Invalid feature name '${feature_name}'." >&2
            echo "       Feature names must be kebab-case (lowercase letters, digits, and hyphens)." >&2
            echo "       Example: user-authentication" >&2
            exit 1
        fi
    fi

    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  New Feature Wizard: ${feature_name}" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2

    # Step 2: Brainstorm or review the spec
    step_brainstorm_or_review "$feature_name"

    # Step 3: Offer to generate tasks
    step_generate_tasks "$feature_name"

    # Step 4: Offer to launch implementation
    step_implement "$feature_name"
}

main "$@"
