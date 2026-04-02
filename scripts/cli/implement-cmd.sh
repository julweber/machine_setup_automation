#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-implement-cmd.sh — Implement the `spec implement` subcommand
#
# Usage (via bin/spec dispatcher):
#   spec implement <feature-name> [options]
#
# Options:
#   --agent <opencode|claude|pi|codex>   Agent to use (default: opencode)
#   --max-iterations <n>           Max Ralph loop iterations (default: 5)
#   --no-tmux                      Disable tmux mode (tmux is on by default)
#   --keep-tmux                    Keep tmux session alive after completion
#   --provider <provider>          Provider (pi only)
#   --model <model>                Model to use (passed through to agent)
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Defaults ──────────────────────────────────────────────────────────────────

AGENT="opencode"
MAX_ITERATIONS=5
FEATURE_NAME=""
PROVIDER=""
MODEL=""
MAX_ITERATION_DURATION=""
NO_TMUX=false
KEEP_TMUX=false

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
  spec implement <feature-name> [options]

Arguments:
  feature-name   Name of the feature to implement (kebab-case, required).

Options:
  --agent <opencode|claude|pi|codex>   Agent to use for the Ralph loop (default: opencode)
  --max-iterations <n>                 Maximum number of Ralph loop iterations (default: 5)
  --max-iteration-duration <s>
  -mid <s>                             Cancel an iteration after this many seconds and start the next (default: disabled)
  --no-tmux                            Disable tmux mode (tmux is enabled by default)
  --keep-tmux                          Keep tmux session alive after ralph exits
  --provider <provider>                LLM provider — only valid when --agent pi
  --model <model>                      Model to use (passed through to the agent CLI)

Examples:
  spec implement user-authentication
  spec implement user-authentication --agent claude --max-iterations 10
  spec implement user-authentication --agent pi --provider openai --model gpt-4o
  spec implement user-authentication --agent codex --model gpt-4o
EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)
                if [ -z "${2:-}" ]; then
                    echo "Error: --agent requires a value." >&2
                    print_usage
                    exit 1
                fi
                AGENT="$2"
                shift 2
                ;;
            --max-iterations)
                if [ -z "${2:-}" ]; then
                    echo "Error: --max-iterations requires a value." >&2
                    print_usage
                    exit 1
                fi
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            --provider)
                if [ -z "${2:-}" ]; then
                    echo "Error: --provider requires a value." >&2
                    print_usage
                    exit 1
                fi
                PROVIDER="$2"
                shift 2
                ;;
            --model)
                if [ -z "${2:-}" ]; then
                    echo "Error: --model requires a value." >&2
                    print_usage
                    exit 1
                fi
                MODEL="$2"
                shift 2
                ;;
            --max-iteration-duration|-mid)
                if [ -z "${2:-}" ]; then
                    echo "Error: --max-iteration-duration requires a value." >&2
                    print_usage
                    exit 1
                fi
                MAX_ITERATION_DURATION="$2"
                shift 2
                ;;
            --no-tmux)
                NO_TMUX=true
                shift
                ;;
            --keep-tmux)
                KEEP_TMUX=true
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option '$1'." >&2
                print_usage
                exit 1
                ;;
            *)
                if [ -z "$FEATURE_NAME" ]; then
                    FEATURE_NAME="$1"
                else
                    echo "Error: Unexpected argument '$1'." >&2
                    print_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# ── Validation ─────────────────────────────────────────────────────────────────

validate_feature_name() {
    if [ -z "$FEATURE_NAME" ]; then
        echo "Error: feature-name is required." >&2
        print_usage
        exit 1
    fi
}

validate_agent_value() {
    case "$AGENT" in
        opencode|claude|pi|codex) ;;
        *)
            echo "Error: Invalid --agent value '${AGENT}'." >&2
            echo "       Valid options: opencode, claude, pi, codex" >&2
            exit 1
            ;;
    esac
}

validate_max_iterations() {
    # Must be a positive integer
    if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations must be a positive integer, got '${MAX_ITERATIONS}'." >&2
        echo "       Valid range: any positive integer (e.g. 1, 5, 20)" >&2
        exit 1
    fi
    if [ "$MAX_ITERATIONS" -le 0 ]; then
        echo "Error: --max-iterations must be a positive integer greater than 0, got '${MAX_ITERATIONS}'." >&2
        echo "       Valid range: any positive integer (e.g. 1, 5, 20)" >&2
        exit 1
    fi
}

validate_max_iteration_duration() {
    if [ -z "$MAX_ITERATION_DURATION" ]; then
        return
    fi
    if ! [[ "$MAX_ITERATION_DURATION" =~ ^[0-9]+$ ]] || [ "$MAX_ITERATION_DURATION" -le 0 ]; then
        echo "Error: --max-iteration-duration must be a positive integer (seconds), got '${MAX_ITERATION_DURATION}'." >&2
        exit 1
    fi
}

validate_provider_flag() {
    # --provider is only allowed when --agent pi
    if [ -n "$PROVIDER" ] && [ "$AGENT" != "pi" ]; then
        echo "Error: --provider is only supported with --agent pi." >&2
        echo "       You specified --agent ${AGENT} with --provider ${PROVIDER}." >&2
        echo "       Either remove --provider or use --agent pi." >&2
        exit 1
    fi
}

validate_tasks_file() {
    local tasks_file="${PWD}/tasks/${FEATURE_NAME}/tasks.yaml"
    if [ ! -f "$tasks_file" ]; then
        echo "Error: tasks file not found: ${tasks_file}" >&2
        echo "" >&2
        echo "       Generate the task list first by running:" >&2
        echo "         spec generate-tasks ${FEATURE_NAME}" >&2
        echo "       Then run your AI agent with /spec-to-tasks ${FEATURE_NAME}" >&2
        exit 1
    fi
}

validate_tasks_committed() {
    local tasks_file="tasks/${FEATURE_NAME}/tasks.yaml"
    # git status --porcelain returns non-empty if the file is modified/untracked
    local status_output
    status_output="$(git status --porcelain "$tasks_file" 2>/dev/null || true)"
    if [ -n "$status_output" ]; then
        echo "Error: ${tasks_file} has uncommitted changes." >&2
        echo "       Commit tasks.yaml before launching the implementation loop." >&2
        echo "" >&2
        echo "       Run:" >&2
        echo "         git add ${tasks_file}" >&2
        echo "         git commit -m 'feat: add tasks for ${FEATURE_NAME}'" >&2
        exit 1
    fi
    # Also make sure git knows about this file at all (not just untracked-new)
    local ls_files
    ls_files="$(git ls-files "$tasks_file" 2>/dev/null || true)"
    if [ -z "$ls_files" ]; then
        echo "Error: ${tasks_file} is not tracked by git (never committed)." >&2
        echo "       Commit tasks.yaml before launching the implementation loop." >&2
        echo "" >&2
        echo "       Run:" >&2
        echo "         git add ${tasks_file}" >&2
        echo "         git commit -m 'feat: add tasks for ${FEATURE_NAME}'" >&2
        exit 1
    fi
}

validate_agent_cli() {
    if ! command -v "$AGENT" &>/dev/null; then
        echo "Error: Agent CLI '${AGENT}' not found in PATH." >&2
        echo "" >&2
        case "$AGENT" in
            opencode)
                echo "       Install opencode: https://github.com/sst/opencode" >&2
                ;;
            claude)
                echo "       Install Claude CLI: https://github.com/anthropics/anthropic-quickstarts" >&2
                ;;
            pi)
                echo "       Install pi: https://github.com/mariozechner/pi-coding-agent" >&2
                ;;
            codex)
                echo "       Install Codex CLI: https://github.com/openai/codex" >&2
                ;;
        esac
        exit 1
    fi
}

# ── Worktree management ────────────────────────────────────────────────────────

setup_worktree() {
    local project_root="$1"
    local project_name="$2"

    local branch_name="feat/${FEATURE_NAME}"
    local worktree_path
    worktree_path="$(cd "${project_root}/.." && pwd)/${project_name}-feat-${FEATURE_NAME}"

    echo "Branch:        ${branch_name}" >&2
    echo "Worktree path: ${worktree_path}" >&2
    echo "" >&2

    # Check if the branch already exists; create it if not
    if ! git -C "$project_root" show-ref --quiet --verify "refs/heads/${branch_name}" 2>/dev/null; then
        echo "Creating branch: ${branch_name}" >&2
        git -C "$project_root" branch "$branch_name" 2>/dev/null || true
        echo "Branch created." >&2
    else
        echo "Branch already exists: ${branch_name}" >&2
    fi

    # Check if a worktree is already registered at that path
    local existing_worktree
    existing_worktree="$(git -C "$project_root" worktree list --porcelain 2>/dev/null \
        | grep -F "worktree ${worktree_path}" || true)"

    if [ -d "$worktree_path" ] || [ -n "$existing_worktree" ]; then
        echo "Worktree already exists at: ${worktree_path}" >&2
        echo "Reusing existing worktree." >&2
    else
        echo "Creating worktree at: ${worktree_path}" >&2
        git -C "$project_root" worktree add "$worktree_path" "$branch_name" >&2
        echo "Worktree created." >&2
    fi

    echo "$worktree_path"
}

# ── Ralph loop launcher ────────────────────────────────────────────────────────

launch_ralph() {
    local worktree_path="$1"

    local ralph_script="${worktree_path}/scripts/ralph/ralph.sh"
    if [ ! -f "$ralph_script" ]; then
        # Fall back to the ralph.sh relative to this script's own location
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        ralph_script="${script_dir}/ralph/ralph.sh"
    fi

    if [ ! -f "$ralph_script" ]; then
        echo "Error: ralph.sh not found." >&2
        echo "       Expected at: ${worktree_path}/scripts/ralph/ralph.sh" >&2
        exit 1
    fi

    echo ""
    echo "Launching Ralph loop in worktree: ${worktree_path}"
    echo ""

    # Build arguments for ralph.sh
    local ralph_args=(
        "--agent"          "$AGENT"
        "--max-iterations" "$MAX_ITERATIONS"
    )

    if [ -n "$PROVIDER" ]; then
        ralph_args+=("--provider" "$PROVIDER")
    fi

    if [ -n "$MODEL" ]; then
        ralph_args+=("--model" "$MODEL")
    fi

    if [ -n "$MAX_ITERATION_DURATION" ]; then
        ralph_args+=("--max-iteration-duration" "$MAX_ITERATION_DURATION")
    fi

    if [ "$NO_TMUX" = true ]; then
        ralph_args+=("--no-tmux")
    fi

    if [ "$KEEP_TMUX" = true ]; then
        ralph_args+=("--keep-tmux")
    fi

    ralph_args+=("$FEATURE_NAME")

    # Run ralph from within the worktree directory
    cd "$worktree_path"
    exec "$ralph_script" "${ralph_args[@]}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    # Validate feature name first (required positional arg)
    validate_feature_name

    # Validate options before any filesystem/git operations
    validate_agent_value
    validate_max_iterations
    validate_max_iteration_duration
    validate_provider_flag

    # Validate the agent CLI is available in PATH (before git ops)
    validate_agent_cli

    # Validate tasks.yaml exists and is committed (relative to CWD = project root)
    validate_tasks_file
    validate_tasks_committed

    # Resolve project root and name
    local project_root
    project_root="$(pwd)"
    local project_name
    project_name="$(basename "$project_root")"

    echo ""
    echo "###### CONFIGURATION ######"
    echo ""
    echo "Feature:         ${FEATURE_NAME}"
    echo "Agent:           ${AGENT}"
    echo "Max iterations:  ${MAX_ITERATIONS}"
    echo "Provider:        ${PROVIDER:-default}"
    echo "Model:           ${MODEL:-default}"
    echo "tmux mode:       $( [ "$NO_TMUX" = true ] && echo "disabled" || echo "enabled" )"
    echo "Project root:    ${project_root}"
    echo "Project name:    ${project_name}"
    echo "###########################"
    echo ""

    # Set up worktree (create branch + worktree if needed, reuse if exists)
    local worktree_path
    worktree_path="$(setup_worktree "$project_root" "$project_name")"

    # Launch the Ralph loop (exec — replaces this process)
    launch_ralph "$worktree_path"
}

main "$@"
