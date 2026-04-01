#!/usr/bin/env bash

# Ralph Loop - Autonomous AI coding agent loop
# Usage: ./ralph.sh [--agent <agent>] [--max-iterations <n>] [--provider <provider>] [--model <model>] [--tmux] [--task-file <path>] <feature-name>
# Agents: opencode (default), claude, pi, codex
# Provider/Model mapping:
#   - opencode: Uses --model in format 'provider/model' (--provider is ignored)
#   - claude: Uses --model with model name/alias (--provider is ignored)
#   - pi: Supports both --provider and --model independently
#   - codex: Uses --model with model name (--provider is ignored)
# tmux mode: --tmux runs agents in TUI mode inside a tmux session for monitoring/steering

set -e

# ========================================
# 1. CONFIGURATION & SETUP
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Allow env overrides (used by test harness to inject fixture paths)
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROMPT_FILE="${PROMPT_FILE:-$SCRIPT_DIR/prompt.md}"

# Defaults
AGENT="opencode"
MAX_ITERATIONS=5
FEATURE_NAME="${FEATURE_NAME:-}"
TASK_FILE=""
CONTEXT=""
LOG_FILE=""
DETECTED_SIGNAL=""
VERBOSE=false
USE_TMUX=false
KEEP_TMUX=false
IDLE_TIMEOUT=120

# ========================================
# 2. ARGUMENT PARSING
# ========================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)
        AGENT="$2"
        shift 2
        ;;
      --max-iterations)
        MAX_ITERATIONS="$2"
        shift 2
        ;;
      --provider)
        PROVIDER="$2"
        shift 2
        ;;
      --model)
        MODEL="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --tmux)
        USE_TMUX=true
        shift
        ;;
      --keep-tmux)
        KEEP_TMUX=true
        shift
        ;;
      --idle-timeout)
        IDLE_TIMEOUT="$2"
        shift 2
        ;;
      --task-file)
        TASK_FILE="$2"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1" >&2
        print_usage
        exit 1
        ;;
      *)
        FEATURE_NAME="$1"
        shift
        ;;
    esac
  done
}

print_usage() {
  echo "Usage: $0 [options] <feature-name>" >&2
  echo "       $0 [options] --task-file <path>" >&2
  echo "" >&2
  echo "Arguments:" >&2
  echo "  feature-name             Name of the feature (mutually exclusive with --task-file)" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --agent <agent>          Agent to use: opencode (default), claude, pi, codex" >&2
  echo "  --max-iterations <n>     Max loop iterations (default: 5)" >&2
  echo "  --provider <provider>    LLM provider (pi agent only)" >&2
  echo "  --model <model>          Model to use (passed through to agent)" >&2
  echo "  --task-file <path>       Path to tasks YAML file (alternative to feature-name)" >&2
  echo "" >&2
  echo "tmux mode:" >&2
  echo "  --tmux                   Run agents in TUI mode inside a tmux session" >&2
  echo "  --keep-tmux              Keep tmux session alive after ralph exits" >&2
  echo "  --idle-timeout <s>       Seconds of no output before treating agent as done (default: 120)" >&2
}

# Parse arguments from command line
parse_args "$@"

# ========================================
# 3. VALIDATION FUNCTIONS
# ========================================

validate_tasks_file() {
  local tasks_file="$PROJECT_ROOT/tasks/$FEATURE_NAME/tasks.yaml"
  if [ ! -f "$tasks_file" ]; then
    echo "Error: tasks file not found: $tasks_file" >&2
    exit 1
  fi
}

validate_yq() {
  if ! command -v yq &>/dev/null; then
    echo "Error: 'yq' is required but not installed. Please install yq." >&2
    exit 1
  fi
}

validate_agent() {
  case "$AGENT" in
    opencode|claude|pi|codex) ;;
    *)
      echo "Error: unknown agent '$AGENT'. Valid options: opencode, claude, pi, codex" >&2
      exit 1
      ;;
  esac
}

validate_tmux() {
  if ! command -v tmux &>/dev/null; then
    echo "Error: 'tmux' is required for --tmux mode but not found in PATH" >&2
    exit 1
  fi
}

validate_agent_cli() {
  if ! command -v "$AGENT" &>/dev/null; then
    echo "Error: agent CLI '$AGENT' not found in PATH" >&2
    exit 1
  fi
}

validate_prompt_file() {
  if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: prompt.md not found at $PROMPT_FILE" >&2
    exit 1
  fi
}

# ========================================
# 4. HELPER FUNCTIONS
# ========================================

build_context() {
  local proj_dir="$PROJECT_ROOT/specification/project"
  local output=""

  # ── Layer 1: Available Specification Files ────────────────────────────────────
  # List all available spec files so the agent can read them on demand.
  output+="# Available Specification Files"$'\n\n'
  output+="Read any of these files as needed. Paths are relative to the project root."$'\n\n'

  # Project spec files
  output+="## Project Specification"$'\n\n'
  local proj_files=(description concepts architecture conventions test-strategy lessons-learned)
  for name in "${proj_files[@]}"; do
    local f="$proj_dir/$name.md"
    if [ -f "$f" ]; then
      output+="- specification/project/$name.md"$'\n'
    fi
  done
  output+=$'\n'

  # Feature spec files
  local feat_dir="$PROJECT_ROOT/specification/features/$FEATURE_NAME"
  local behaviors_file="$feat_dir/behaviors.md"
  if [ -f "$behaviors_file" ]; then
    output+="## Feature Specification ($FEATURE_NAME)"$'\n\n'
    output+="- specification/features/$FEATURE_NAME/behaviors.md"$'\n'

    local tests_file="$feat_dir/tests.md"
    if [ -f "$tests_file" ]; then
      output+="- specification/features/$FEATURE_NAME/tests.md"$'\n'
    fi

    while IFS= read -r -d '' f; do
      local base
      base="$(basename "$f")"
      output+="- specification/features/$FEATURE_NAME/$base"$'\n'
    done < <(find "$feat_dir" -maxdepth 1 -name '*.md' -not -name 'behaviors.md' -not -name 'tests.md' | sort -z)
    output+=$'\n'
  else
    echo "Warning: behaviors.md not found for feature '$FEATURE_NAME'. Skipping feature spec layer." >&2
  fi

  # ── Layer 2: Implementation Progress ─────────────────────────────────────────
  # Inject progress.txt; silently skip if absent.
  local progress_file
  if [ -n "$TASK_FILE" ]; then
    progress_file="$(dirname "$TASK_FILE")/progress.txt"
  else
    progress_file="$PROJECT_ROOT/tasks/$FEATURE_NAME/progress.txt"
  fi
  if [ -f "$progress_file" ]; then
    output+="# Implementation Progress"$'\n\n'
    output+="## progress"$'\n\n'
    output+="$(cat "$progress_file")"$'\n\n'
  fi

  # ── Layer 3: Agent Instructions ───────────────────────────────────────────────
  # Always present (validated by validate_prompt_file before build_context is called).
  output+="# Agent Instructions"$'\n\n'
  output+="## instructions"$'\n\n'
  output+="$(cat "$PROMPT_FILE")"$'\n'

  printf '%s' "$output"
}

run_agent_streaming() {
  local iteration="$1"
  DETECTED_SIGNAL=""

  local fifo
  fifo=$(mktemp -u "/tmp/ralph-fifo-XXXXXX")
  mkfifo "$fifo"

  # Write log header with timestamp
  {
    echo "----------- AGENT OUTPUT for iteration $iteration ---------------"
    echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
  } >> "$LOG_FILE"

  # Launch agent in background, writing to FIFO
  local agent_pid=""
  local agent_cmd=""

  case "$AGENT" in
    opencode)
      agent_cmd="opencode run --dir \"$PROJECT_ROOT\""
      ;;
    claude)
      agent_cmd="claude --print"
      ;;
    pi)
      agent_cmd="pi --print --session-dir \"$PROJECT_ROOT/tasks/agent_logs\""
      ;;
    codex)
      agent_cmd="codex exec"
      ;;
  esac

  # Apply provider/model arguments based on agent type
  case "$AGENT" in
    opencode|claude|codex)
      if [ -n "${MODEL:-}" ]; then
        agent_cmd="$agent_cmd --model $MODEL"
      fi
      ;;
    pi)
      if [ -n "${PROVIDER:-}" ]; then
        agent_cmd="$agent_cmd --provider $PROVIDER"
      fi
      if [ -n "${MODEL:-}" ]; then
        agent_cmd="$agent_cmd --model $MODEL"
      fi
      ;;
  esac

  eval "$agent_cmd" < <(echo "$CONTEXT") > "$fifo" 2>&1 &
  agent_pid=$!

  # Read from FIFO line-by-line, log everything, kill on signal
  while IFS= read -r line; do
    echo "$line" >> "$LOG_FILE"

    if [[ "$line" == *'<promise>SUB-TASK-COMPLETE</promise>'* ]]; then
      DETECTED_SIGNAL="SUB-TASK-COMPLETE"
      break
    elif [[ "$line" == *'<promise>COMPLETE</promise>'* ]]; then
      DETECTED_SIGNAL="COMPLETE"
      break
    elif [[ "$line" == *'<promise>FAILED</promise>'* ]]; then
      DETECTED_SIGNAL="FAILED"
      break
    fi
  done < "$fifo"

  # Kill the agent process if it's still running
  kill_agent_if_running "$agent_pid"

  # Write log footer with timestamp
  {
    echo ""
    echo "----------- AGENT OUTPUT END for iteration $iteration -----------"
    echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Detected signal: ${DETECTED_SIGNAL:-NONE}"
    echo ""
  } >> "$LOG_FILE"

  # Clean up FIFO
  rm -f "$fifo"
}

kill_agent_if_running() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

# ========================================
# 4b. TMUX MODE FUNCTIONS
# ========================================

setup_tmux_session() {
  local session="ralph-${FEATURE_NAME}"
  TMUX_SESSION="$session"

  if tmux has-session -t "$session" 2>/dev/null; then
    # Reuse existing session, clear agent pane
    tmux send-keys -t "${session}:0.0" C-c Enter
    sleep 0.5
    tmux send-keys -t "${session}:0.0" 'clear' Enter
    sleep 0.3
  else
    # Create session with explicit size to support detached creation
    tmux new-session -d -s "$session" -c "$PROJECT_ROOT" -x 220 -y 55

    # Split for task monitor pane (bottom 15 lines)
    if tmux split-window -t "$session" -v -l 15 -c "$PROJECT_ROOT" 2>/dev/null; then
      # Start task monitor in bottom pane
      tmux send-keys -t "${session}:0.1" \
        "watch -n2 'yq e \".tasks[] | [.id, .status, .title]\" \"${TASK_FILE:-$PROJECT_ROOT/tasks/$FEATURE_NAME/tasks.yaml}\"'" Enter
      # Select agent pane
      tmux select-pane -t "${session}:0.0"
    else
      echo "  Note: could not split pane (session may be too small). Using single pane." >&2
    fi
  fi
  echo ""
  echo "  tmux session: $session"
  echo "  Attach to monitor/steer: tmux attach -t $session"
  echo ""
}

cleanup_tmux_session() {
  local session="ralph-${FEATURE_NAME}"
  if [ "$KEEP_TMUX" = true ]; then
    echo "tmux session preserved: tmux attach -t $session"
  else
    tmux kill-session -t "$session" 2>/dev/null || true
  fi
  # Clean up temp files
  rm -f "/tmp/ralph-signal-$$" "/tmp/ralph-context-$$.md"
}

kill_tmux_agent() {
  local target="$1"
  local pane_pid
  pane_pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null) || return 0
  local agent_pid
  agent_pid=$(pgrep -P "$pane_pid" 2>/dev/null | head -1) || true
  if [ -n "$agent_pid" ]; then
    kill "$agent_pid" 2>/dev/null || true
    sleep 1
    kill -9 "$agent_pid" 2>/dev/null || true
  fi
}

build_tmux_agent_cmd() {
  local context_file="$1"
  local agent_cmd=""

  case "$AGENT" in
    claude)
      agent_cmd="claude --permission-mode auto"
      [ -n "${MODEL:-}" ] && agent_cmd="$agent_cmd --model $MODEL"
      agent_cmd="$agent_cmd --system-prompt \"\$(cat $context_file)\" \"Begin working on the next task per the system prompt instructions\""
      ;;
    pi)
      agent_cmd="pi --session-dir \"$PROJECT_ROOT/tasks/agent_logs\""
      [ -n "${PROVIDER:-}" ] && agent_cmd="$agent_cmd --provider $PROVIDER"
      [ -n "${MODEL:-}" ] && agent_cmd="$agent_cmd --model $MODEL"
      agent_cmd="$agent_cmd @$context_file \"Begin working on the next task per the instructions\""
      ;;
    opencode)
      agent_cmd="opencode --prompt \"\$(cat $context_file)\""
      [ -n "${MODEL:-}" ] && agent_cmd="$agent_cmd --model $MODEL"
      ;;
    codex)
      agent_cmd="codex --full-auto"
      [ -n "${MODEL:-}" ] && agent_cmd="$agent_cmd --model $MODEL"
      agent_cmd="$agent_cmd \"\$(cat $context_file)\""
      ;;
  esac

  echo "$agent_cmd"
}

run_agent_streaming_tmux() {
  local iteration="$1"
  DETECTED_SIGNAL=""

  local session="ralph-${FEATURE_NAME}"
  local target="${session}:0.0"
  local signal_file="/tmp/ralph-signal-$$"
  local context_file="/tmp/ralph-context-$$.md"

  rm -f "$signal_file"

  # Write context to temp file (tmux send-keys can't pipe stdin)
  printf '%s' "$CONTEXT" > "$context_file"

  # Write log header
  {
    echo "----------- AGENT OUTPUT for iteration $iteration (tmux TUI) ---------------"
    echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Agent: $AGENT (TUI mode)"
    echo ""
  } >> "$LOG_FILE"

  # Build agent TUI command
  local agent_tui_cmd
  agent_tui_cmd=$(build_tmux_agent_cmd "$context_file")

  # Clear pane and launch agent
  tmux send-keys -t "$target" 'clear' Enter
  sleep 0.3
  tmux send-keys -t "$target" "$agent_tui_cmd" Enter

  # Start watcher in background
  "$SCRIPT_DIR/tmux-watcher.sh" "$target" "$signal_file" "$IDLE_TIMEOUT" &
  local watcher_pid=$!

  # Poll signal file
  while [ ! -f "$signal_file" ]; do
    sleep 0.5
  done
  DETECTED_SIGNAL=$(cat "$signal_file")

  # Stop watcher
  kill "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true

  # Capture pane content to log before killing agent
  {
    echo "--- tmux pane capture ---"
    tmux capture-pane -t "$target" -p -S -500 2>/dev/null || true
    echo "--- end pane capture ---"
  } >> "$LOG_FILE"

  # Kill the agent TUI
  kill_tmux_agent "$target"

  # Write log footer
  {
    echo ""
    echo "----------- AGENT OUTPUT END for iteration $iteration -----------"
    echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Detected signal: ${DETECTED_SIGNAL:-NONE}"
    echo ""
  } >> "$LOG_FILE"

  # Clean up signal file (keep context file for next iteration overwrite)
  rm -f "$signal_file"
}

display_configuration() {
  echo "###### CONFIGURATION ######"
  echo ""
  echo "Feature:         $FEATURE_NAME"
  echo "Agent:           $AGENT"
  echo "Max iterations:  $MAX_ITERATIONS"
  echo "Provider:        ${PROVIDER:-default}"
  echo "Model:           ${MODEL:-default}"
  echo "Project root:    $PROJECT_ROOT"
  if [ -n "$TASK_FILE" ]; then
    echo "Tasks file:      $TASK_FILE"
  else
    echo "Tasks file:      $PROJECT_ROOT/tasks/$FEATURE_NAME/tasks.yaml"
  fi
  echo "Log file:        $LOG_FILE"
  echo "Agent CLI:       $(command -v "$AGENT")"
  if [ "$USE_TMUX" = true ]; then
    echo "tmux mode:       enabled"
    echo "tmux session:    ralph-${FEATURE_NAME}"
    echo "Idle timeout:    ${IDLE_TIMEOUT}s"
    echo "Keep session:    $KEEP_TMUX"
  fi
  echo "###########################"
  echo ""
}

log_iteration_header() {
  local iteration="$1"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "==============================================================="
  echo "  Iteration $iteration of $MAX_ITERATIONS"
  echo "  Started at: $timestamp"
  echo "==============================================================="
  echo ""
}

handle_signal_complete() {
  local iteration="$1"
  echo ""
  echo "=========================================="
  echo "  Ralph completed all tasks!"
  echo "  Completed at iteration $iteration of $MAX_ITERATIONS"
  echo "=========================================="
}

handle_signal_failed() {
  local iteration="$1"
  echo ""
  echo "=========================================="
  echo "  Ralph failed: no eligible tasks remaining."
  echo "  See log: $LOG_FILE"
  echo "=========================================="
}

handle_signal_subtask_complete() {
  echo ""
  echo "  Task completed. Moving to next iteration..."
  echo ""
}

handle_signal_unrecognized() {
  local iteration="$1"
  echo ""
  echo "  WARNING: Agent did not emit a recognized signal."
  echo "  Expected one of: SUB-TASK-COMPLETE, COMPLETE, FAILED"
  echo "  Continuing to next iteration anyway..."
  echo ""
}

# ========================================
# 5. MAIN EXECUTION
# ========================================

main() {
  # Resolve task file path and feature name
  if [ -n "$TASK_FILE" ] && [ -n "$FEATURE_NAME" ]; then
    echo "Error: --task-file and <feature-name> are mutually exclusive." >&2
    print_usage
    exit 1
  fi

  if [ -n "$TASK_FILE" ]; then
    # --task-file mode: resolve paths from the provided file
    if [ ! -f "$TASK_FILE" ]; then
      echo "Error: task file not found: $TASK_FILE" >&2
      exit 1
    fi
    TASK_FILE="$(cd "$(dirname "$TASK_FILE")" && pwd)/$(basename "$TASK_FILE")"
    local task_file_dir
    task_file_dir="$(dirname "$TASK_FILE")"
    FEATURE_NAME="$(basename "$task_file_dir")"
    LOG_FILE="$task_file_dir/agent_output.log"
    mkdir -p "$task_file_dir"
  elif [ -n "$FEATURE_NAME" ]; then
    # feature-name mode: use conventional paths
    LOG_FILE="$PROJECT_ROOT/tasks/$FEATURE_NAME/agent_output.log"
    mkdir -p "$PROJECT_ROOT/tasks/$FEATURE_NAME"
    validate_tasks_file
  else
    echo "Error: either <feature-name> or --task-file is required." >&2
    print_usage
    exit 1
  fi

  validate_yq
  validate_agent
  validate_agent_cli
  validate_prompt_file

  if [ "$USE_TMUX" = true ]; then
    validate_tmux
    setup_tmux_session
    trap cleanup_tmux_session EXIT
  fi

  display_configuration

  echo "Starting Ralph Loop — Max iterations: $MAX_ITERATIONS"
  echo ""

  for i in $(seq 1 "$MAX_ITERATIONS"); do
    log_iteration_header "$i"

    CONTEXT="$(build_context)"

    if [ "$VERBOSE" = true ]; then
      echo "============ FULL PROMPT ============"
      printf '%s\n' "$CONTEXT"
      echo "======================================"
      echo ""
    fi

    set +e
    if [ "$USE_TMUX" = true ]; then
      run_agent_streaming_tmux "$i"
    else
      run_agent_streaming "$i"
    fi
    set -e

    echo "Agent output logged to: $LOG_FILE (at $(date '+%Y-%m-%d %H:%M:%S'))"

    case "$DETECTED_SIGNAL" in
      COMPLETE)
        handle_signal_complete "$i"
        exit 0
        ;;
      FAILED)
        handle_signal_failed "$i"
        exit 1
        ;;
      SUB-TASK-COMPLETE)
        handle_signal_subtask_complete
        ;;
      IDLE)
        echo ""
        echo "  Agent idle for ${IDLE_TIMEOUT}s — treating as task complete."
        echo "  Continuing to next iteration..."
        echo ""
        ;;
      *)
        handle_signal_unrecognized "$i"
        ;;
    esac
  done

  echo ""
  echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
