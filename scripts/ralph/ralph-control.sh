#!/usr/bin/env bash

# Ralph Agent Control Commands
# Provides convenient commands for monitoring and controlling Ralph agent sessions
# Usage: ./ralph-control.sh <command> [options]

set -e

# ========================================
# 1. CONFIGURATION
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SESSION_DIR="$PROJECT_ROOT/tasks/agent_sessions"

# ========================================
# 2. HELPER FUNCTIONS
# ========================================

get_session_file() {
  local feature="$1"
  echo "$SESSION_DIR/${feature}.session"
}

get_session_name() {
  local feature="$1"
  if [ -f "$(get_session_file "$feature")" ]; then
    grep "^session_name=" "$(get_session_file "$feature")" | cut -d'=' -f2
  else
    echo ""
  fi
}

get_agent_from_session() {
  local feature="$1"
  if [ -f "$(get_session_file "$feature")" ]; then
    grep "^agent=" "$(get_session_file "$feature")" | cut -d'=' -f2
  else
    echo ""
  fi
}

get_log_file() {
  local feature="$1"
  if [ -f "$(get_session_file "$feature")" ]; then
    grep "^log_file=" "$(get_session_file "$feature")" | cut -d'=' -f2
  else
    echo "$PROJECT_ROOT/tasks/$feature/agent_output.log"
  fi
}

list_sessions() {
  echo "Active Ralph Agent Sessions"
  echo "============================"
  echo ""

  if [ ! -d "$SESSION_DIR" ]; then
    echo "No sessions directory found."
    return
  fi

  local count=0
  for session_file in "$SESSION_DIR"/*.session; do
    if [ -f "$session_file" ]; then
      local feature
      feature=$(basename "$session_file" .session)
      local session_name
      session_name=$(get_session_name "$feature")
      local agent
      agent=$(get_agent_from_session "$feature")
      local status="unknown"

      # Check if tmux session exists
      if command -v tmux &>/dev/null && [ -n "$session_name" ]; then
        if tmux has-session -t "$session_name" 2>/dev/null; then
          status="running"
        else
          status="completed"
        fi
      fi

      echo "Feature: $feature"
      echo "  Agent:   $agent"
      echo "  Session: $session_name"
      echo "  Status:  $status"
      echo ""
      ((count++))
    fi
  done

  if [ $count -eq 0 ]; then
    echo "No active sessions found."
  else
    echo "Total: $count session(s)"
  fi
}

# ========================================
# 3. COMMANDS
# ========================================

cmd_attach() {
  local feature="$1"
  if [ -z "$feature" ]; then
    echo "Error: feature name required"
    echo "Usage: $0 attach <feature-name>"
    exit 1
  fi

  local session_name
  session_name=$(get_session_name "$feature")

  if [ -z "$session_name" ]; then
    echo "Error: no active session found for feature '$feature'"
    echo "Run 'ralph-tmux.sh' first to start a session."
    exit 1
  fi

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Error: tmux session '$session_name' does not exist"
    echo "The session may have completed or been killed."
    exit 1
  fi

  tmux attach -t "$session_name"
}

cmd_status() {
  local feature="$1"
  if [ -z "$feature" ]; then
    echo "Error: feature name required"
    echo "Usage: $0 status <feature-name>"
    exit 1
  fi

  local session_name
  session_name=$(get_session_name "$feature")

  if [ -z "$session_name" ]; then
    echo "No active session found for feature '$feature'"
    return
  fi

  local agent
  agent=$(get_agent_from_session "$feature")
  local log_file
  log_file=$(get_log_file "$feature")
  local status="unknown"

  if tmux has-session -t "$session_name" 2>/dev/null; then
    status="running"
    echo "Session: $session_name"
    echo "Agent:   $agent"
    echo "Status:  $status"
    echo ""
    echo "Recent log output:"
    echo "------------------"
    if [ -f "$log_file" ]; then
      tail -20 "$log_file"
    else
      echo "Log file not found: $log_file"
    fi
  else
    status="completed"
    echo "Session: $session_name"
    echo "Agent:   $agent"
    echo "Status:  $status (session no longer active)"
    echo ""
    echo "Last log output:"
    echo "----------------"
    if [ -f "$log_file" ]; then
      tail -30 "$log_file"
    else
      echo "Log file not found: $log_file"
    fi
  fi
}

cmd_logs() {
  local feature="$1"
  if [ -z "$feature" ]; then
    echo "Error: feature name required"
    echo "Usage: $0 logs <feature-name>"
    exit 1
  fi

  local log_file
  log_file=$(get_log_file "$feature")

  if [ ! -f "$log_file" ]; then
    echo "Error: log file not found: $log_file"
    exit 1
  fi

  tail -f "$log_file"
}

cmd_inject() {
  local feature="$1"
  local input="${*:2}"

  if [ -z "$feature" ]; then
    echo "Error: feature name required"
    echo "Usage: $0 inject <feature-name> <input>"
    exit 1
  fi

  if [ -z "$input" ]; then
    echo "Error: input required"
    echo "Usage: $0 inject <feature-name> <input>"
    exit 1
  fi

  local session_name
  session_name=$(get_session_name "$feature")

  if [ -z "$session_name" ]; then
    echo "Error: no active session found for feature '$feature'"
    exit 1
  fi

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Error: tmux session '$session_name' does not exist"
    exit 1
  fi

  echo "Injecting input into session: $session_name"
  echo "Input: $input"
  tmux send-keys -t "$session_name" "$input" Enter
}

cmd_stop() {
  local feature="$1"
  if [ -z "$feature" ]; then
    echo "Error: feature name required"
    echo "Usage: $0 stop <feature-name>"
    exit 1
  fi

  local session_name
  session_name=$(get_session_name "$feature")

  if [ -z "$session_name" ]; then
    echo "Error: no active session found for feature '$feature'"
    exit 1
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Stopping session: $session_name"
    tmux kill-session -t "$session_name"
    echo "Session stopped."
  else
    echo "Session '$session_name' not found or already stopped."
  fi
}

cmd_help() {
  echo "Ralph Agent Control Commands"
  echo "============================="
  echo ""
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  attach <feature>      Attach to an active agent session"
  echo "  status <feature>      Show status and recent logs for a feature"
  echo "  logs <feature>        Stream agent logs in real-time"
  echo "  inject <feature> <msg> Send input to the agent (steering)"
  echo "  stop <feature>        Stop the agent session"
  echo "  list                  List all active sessions"
  echo "  help                  Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 attach my-feature      # Attach to monitor the agent"
  echo "  $0 status my-feature      # Check status and recent output"
  echo "  $0 logs my-feature        # Stream logs in real-time"
  echo "  $0 inject my-feature 'Please focus on error handling'"
  echo "  $0 stop my-feature        # Stop the agent"
  echo "  $0 list                   # Show all active sessions"
  echo ""
  echo "To start a session with tmux monitoring, use:"
  echo "  ./ralph-tmux.sh --tmux <feature-name>"
  echo ""
}

# ========================================
# 4. MAIN
# ========================================

if [ $# -eq 0 ]; then
  cmd_help
  exit 0
fi

command="$1"
shift || true

case "$command" in
  attach)
    cmd_attach "$@"
    ;;
  status)
    cmd_status "$@"
    ;;
  logs)
    cmd_logs "$@"
    ;;
  inject)
    cmd_inject "$@"
    ;;
  stop)
    cmd_stop "$@"
    ;;
  list)
    list_sessions
    ;;
  help|--help|-h)
    cmd_help
    ;;
  *)
    echo "Unknown command: $command"
    echo "Run '$0 help' for usage information."
    exit 1
    ;;
esac
