#!/usr/bin/env bash

# Ralph Loop with Tmux-based Agent Monitoring
# Usage: ./ralph-tmux.sh [--agent <agent>] [--max-iterations <n>] [--provider <provider>] [--model <model>] <feature-name>
# Agents: opencode (default), claude, pi
# Provides tmux session management for easy monitoring and steering

set -e

# ========================================
# 1. CONFIGURATION & SETUP
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROMPT_FILE="${PROMPT_FILE:-$SCRIPT_DIR/prompt.md}"

# Defaults
AGENT="opencode"
MAX_ITERATIONS=5
FEATURE_NAME="${FEATURE_NAME:-}"
CONTEXT=""
LOG_FILE=""
DETECTED_SIGNAL=""
VERBOSE=false
USE_TMUX=false
TMUX_SESSION_NAME=""

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
      --tmux-session-name)
        TMUX_SESSION_NAME="$2"
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
  echo "Usage: $0 [--agent <agent>] [--max-iterations <n>] [--provider <provider>] [--model <model>] [--tmux] [--tmux-session-name <name>] <feature-name>" >&2
  echo "" >&2
  echo "Agents: opencode (default), claude, pi" >&2
  echo "Options:" >&2
  echo "  --tmux                    Enable tmux session management for monitoring" >&2
  echo "  --tmux-session-name <name> Custom tmux session name (default: ralph-<agent>-<feature>)" >&2
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
    opencode|claude|pi) ;;
    *)
      echo "Error: unknown agent '$AGENT'. Valid options: opencode, claude, pi" >&2
      exit 1
      ;;
  esac
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

validate_tmux() {
  if [ "$USE_TMUX" = true ] && ! command -v tmux &>/dev/null; then
    echo "Error: tmux is required for tmux mode but not installed" >&2
    exit 1
  fi
}

# ========================================
# 4. TMUX SESSION MANAGEMENT
# ========================================

get_tmux_session_name() {
  local agent="$1"
  local feature="$2"
  if [ -n "$TMUX_SESSION_NAME" ]; then
    echo "$TMUX_SESSION_NAME"
  else
    echo "ralph-${agent}-${feature}"
  fi
}

create_tmux_session() {
  local session_name="$1"
  local agent="$2"
  local project_root="$3"
  local agent_cmd="$4"

  # Create tmux session in detached mode
  tmux new-session -d -s "$session_name" -x 120 -y 40

  # Create a split pane for monitoring
  tmux split-window -t "$session_name" -h

  # Send agent command to first pane
  tmux send-keys -t "${session_name}:0.0" "$agent_cmd" Enter

  # Show status in second pane
  tmux send-keys -t "${session_name}:0.1" "echo 'Ralph Agent Monitor'; echo 'Session: $session_name'; echo 'Agent: $agent'; echo 'Press Ctrl+B then D to detach'; echo ''; tail -f \"$LOG_FILE\"" Enter

  # Focus on agent pane
  tmux select-pane -t "${session_name}:0.0"
}

attach_to_tmux_session() {
  local session_name="$1"
  tmux attach -t "$session_name"
}

kill_tmux_session() {
  local session_name="$1"
  tmux kill-session -t "$session_name" 2>/dev/null || true
}

capture_tmux_output() {
  local session_name="$1"
  tmux capture-pane -t "$session_name" -p
}

send_to_tmux() {
  local session_name="$1"
  local input="$2"
  tmux send-keys -t "$session_name" "$input" Enter
}

get_tmux_pane_content() {
  local session_name="$1"
  local pane_id="$2"
  tmux capture-pane -t "${session_name}:${pane_id}" -p
}

# ========================================
# 5. HELPER FUNCTIONS
# ========================================

build_context() {
  local proj_dir="$PROJECT_ROOT/specification/project"
  local output=""

  # ── Layer 1: Available Specification Files ────────────────────────────────────
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
  if [ ! -f "$behaviors_file" ]; then
    echo "Error: behaviors.md not found for feature '$FEATURE_NAME'." >&2
    return 1
  fi

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

  # ── Layer 2: Implementation Progress ─────────────────────────────────────────
  local progress_file="$PROJECT_ROOT/tasks/$FEATURE_NAME/progress.txt"
  if [ -f "$progress_file" ]; then
    output+="# Implementation Progress"$'\n\n'
    output+="## progress"$'\n\n'
    output+="$(cat "$progress_file")"$'\n\n'
  fi

  # ── Layer 3: Agent Instructions ───────────────────────────────────────────────
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
  esac

  # Apply provider/model arguments based on agent type
  case "$AGENT" in
    opencode|claude)
      if [ -n "$MODEL" ]; then
        agent_cmd="$agent_cmd --model $MODEL"
      fi
      ;;
    pi)
      if [ -n "$PROVIDER" ]; then
        agent_cmd="$agent_cmd --provider $PROVIDER"
      fi
      if [ -n "$MODEL" ]; then
        agent_cmd="$agent_cmd --model $MODEL"
      fi
      ;;
  esac

  # If tmux mode, send command to tmux session instead
  if [ "$USE_TMUX" = true ]; then
    local session_name
    session_name=$(get_tmux_session_name "$AGENT" "$FEATURE_NAME")
    send_to_tmux "$session_name" "$agent_cmd"
  else
    eval "$agent_cmd" < <(echo "$CONTEXT") > "$fifo" 2>&1 &
    agent_pid=$!
  fi

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
  if [ "$USE_TMUX" = false ] && [ -n "$agent_pid" ]; then
    kill_agent_if_running "$agent_pid"
  fi

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

display_configuration() {
  echo "###### CONFIGURATION ######"
  echo ""
  echo "Feature:         $FEATURE_NAME"
  echo "Agent:           $AGENT"
  echo "Max iterations:  $MAX_ITERATIONS"
  echo "Provider:        ${PROVIDER:-default}"
  echo "Model:           ${MODEL:-default}"
  echo "Project root:    $PROJECT_ROOT"
  echo "Tasks file:      $PROJECT_ROOT/tasks/$FEATURE_NAME/tasks.yaml"
  echo "Log file:        $LOG_FILE"
  echo "Agent CLI:       $(command -v "$AGENT")"
  echo "Tmux mode:       $USE_TMUX"
  if [ "$USE_TMUX" = true ]; then
    echo "Session name:    $(get_tmux_session_name "$AGENT" "$FEATURE_NAME")"
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
# 6. MAIN EXECUTION
# ========================================

main() {
  # Update log file path with feature name
  LOG_FILE="$PROJECT_ROOT/tasks/$FEATURE_NAME/agent_output.log"
  mkdir -p "$PROJECT_ROOT/tasks/$FEATURE_NAME"

  validate_tasks_file
  validate_yq
  validate_agent
  validate_agent_cli
  validate_prompt_file
  validate_tmux

  display_configuration

  # Create tmux session if enabled
  if [ "$USE_TMUX" = true ]; then
    local session_name
    session_name=$(get_tmux_session_name "$AGENT" "$FEATURE_NAME")
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
    esac

    # Apply provider/model arguments
    case "$AGENT" in
      opencode|claude)
        if [ -n "$MODEL" ]; then
          agent_cmd="$agent_cmd --model $MODEL"
        fi
        ;;
      pi)
        if [ -n "$PROVIDER" ]; then
          agent_cmd="$agent_cmd --provider $PROVIDER"
        fi
        if [ -n "$MODEL" ]; then
          agent_cmd="$agent_cmd --model $MODEL"
        fi
        ;;
    esac

    create_tmux_session "$session_name" "$AGENT" "$PROJECT_ROOT" "$agent_cmd"
    echo ""
    echo "Tmux session created: $session_name"
    echo "Attach with: tmux attach -t $session_name"
    echo "Or use: ./ralph-control.sh attach $FEATURE_NAME"
    echo ""
  fi

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
    run_agent_streaming "$i"
    set -e

    echo "Agent output logged to: $LOG_FILE (at $(date '+%Y-%m-%d %H:%M:%S'))"

    case "$DETECTED_SIGNAL" in
      COMPLETE)
        handle_signal_complete "$i"
        # Clean up tmux session if enabled
        if [ "$USE_TMUX" = true ]; then
          local session_name
          session_name=$(get_tmux_session_name "$AGENT" "$FEATURE_NAME")
          echo "Cleaning up tmux session..."
          kill_tmux_session "$session_name"
        fi
        exit 0
        ;;
      FAILED)
        handle_signal_failed "$i"
        if [ "$USE_TMUX" = true ]; then
          local session_name
          session_name=$(get_tmux_session_name "$AGENT" "$FEATURE_NAME")
          kill_tmux_session "$session_name"
        fi
        exit 1
        ;;
      SUB-TASK-COMPLETE)
        handle_signal_subtask_complete
        ;;
      *)
        handle_signal_unrecognized "$i"
        ;;
    esac
  done

  echo ""
  echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
  if [ "$USE_TMUX" = true ]; then
    local session_name
    session_name=$(get_tmux_session_name "$AGENT" "$FEATURE_NAME")
    echo "Session still available for inspection: tmux attach -t $session_name"
  fi
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
