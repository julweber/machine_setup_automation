#!/bin/bash

# Feature Implementation Launcher
# Usage: ./scripts/implement-feature.sh [--agent <agent>] [--max-iterations <n>] [--provider <provider>] [--model <model>] <feature-name>
# Provider/Model mapping:
#   - opencode: Uses --model in format 'provider/model' (--provider is ignored)
#   - claude: Uses --model with model name/alias (--provider is ignored)
#   - pi: Supports both --provider and --model independently

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"


# Defaults
AGENT="opencode"
MAX_ITERATIONS=5
FEATURE_NAME=""
TASK_FILE=""
PROVIDER=""
MODEL=""
USE_TMUX=false
KEEP_TMUX=false
IDLE_TIMEOUT=""

# Parse arguments
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
      echo "Usage: $0 [--agent <agent>] [--max-iterations <n>] [--provider <provider>] [--model <model>] [--tmux] [--task-file <path>] <feature-name>" >&2
      exit 1
      ;;
    *)
      FEATURE_NAME="$1"
      shift
      ;;
  esac
done

# Validate mutual exclusivity
if [ -n "$TASK_FILE" ] && [ -n "$FEATURE_NAME" ]; then
  echo "Error: --task-file and <feature-name> are mutually exclusive." >&2
  exit 1
fi

if [ -z "$FEATURE_NAME" ] && [ -z "$TASK_FILE" ]; then
  echo "Error: either <feature-name> or --task-file is required." >&2
  echo "Usage: $0 [--agent <agent>] [--max-iterations <n>] [--task-file <path>] <feature-name>" >&2
  exit 1
fi

# Validate agent
case "$AGENT" in
  opencode|claude|pi|codex) ;;
  *)
    echo "Error: unknown agent '$AGENT'. Valid options: opencode, claude, pi, codex" >&2
    exit 1
    ;;
esac

# Validate yq is available
if ! command -v yq &>/dev/null; then
  echo "Error: 'yq' is required but not installed. Please install yq." >&2
  exit 1
fi

if [ -n "$TASK_FILE" ]; then
  # --task-file mode: skip worktree, launch ralph directly
  if [ ! -f "$TASK_FILE" ]; then
    echo "Error: task file not found: $TASK_FILE" >&2
    exit 1
  fi

  TASK_FILE="$(cd "$(dirname "$TASK_FILE")" && pwd)/$(basename "$TASK_FILE")"
  TASK_FILE_DIR="$(dirname "$TASK_FILE")"
  FEATURE_NAME="$(basename "$TASK_FILE_DIR")"

  echo "###### CONFIGURATION ######"
  echo ""
  echo "Feature:         $FEATURE_NAME (derived from task file)"
  echo "Task file:       $TASK_FILE"
  echo "Agent:           $AGENT"
  echo "Max iterations:  $MAX_ITERATIONS"
  echo "Provider:        ${PROVIDER:-default}"
  echo "Model:           ${MODEL:-default}"
  echo "###########################"
  echo ""

  # Find ralph.sh relative to this script
  RALPH_SCRIPT="$SCRIPT_DIR/ralph/ralph.sh"
  if [ ! -f "$RALPH_SCRIPT" ]; then
    echo "Error: ralph.sh not found at $RALPH_SCRIPT" >&2
    exit 1
  fi

  echo ""
  echo "Launching ralph loop with task file..."
  echo ""

  RALPH_ARGS=("--agent" "$AGENT" "--max-iterations" "$MAX_ITERATIONS" "--task-file" "$TASK_FILE")

  if [ -n "$PROVIDER" ]; then
    RALPH_ARGS+=("--provider" "$PROVIDER")
  fi

  if [ -n "$MODEL" ]; then
    RALPH_ARGS+=("--model" "$MODEL")
  fi

  if [ "$USE_TMUX" = true ]; then
    RALPH_ARGS+=("--tmux")
  fi

  if [ "$KEEP_TMUX" = true ]; then
    RALPH_ARGS+=("--keep-tmux")
  fi

  if [ -n "$IDLE_TIMEOUT" ]; then
    RALPH_ARGS+=("--idle-timeout" "$IDLE_TIMEOUT")
  fi

  cd "$TASK_FILE_DIR"
  exec "$RALPH_SCRIPT" "${RALPH_ARGS[@]}"
else
  # feature-name mode: validate tasks file, set up worktree
  TASKS_FILE="$PROJECT_ROOT/tasks/$FEATURE_NAME/tasks.yaml"
  if [ ! -f "$TASKS_FILE" ]; then
    echo "Error: tasks file not found: $TASKS_FILE" >&2
    echo "Run /spec-to-tasks $FEATURE_NAME within your coding agent first to generate the task list." >&2
    exit 1
  fi

  # Derive project name and paths
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  BRANCH_NAME="feat/$FEATURE_NAME"
  WORKTREE_PATH="$(cd "$PROJECT_ROOT/.." && pwd)/${PROJECT_NAME}-feat-${FEATURE_NAME}"
  RALPH_SCRIPT="$WORKTREE_PATH/scripts/ralph/ralph.sh"

  echo "###### CONFIGURATION ######"
  echo ""
  echo "Feature:         $FEATURE_NAME"
  echo "Agent:           $AGENT"
  echo "Max iterations:  $MAX_ITERATIONS"
  echo "Provider:        ${PROVIDER:-default}"
  echo "Model:           ${MODEL:-default}"
  echo "Project root:    $PROJECT_ROOT"
  echo "Project name:    $PROJECT_NAME"
  echo "Branch:          $BRANCH_NAME"
  echo "Worktree path:   $WORKTREE_PATH"
  echo "Ralph script path: $RALPH_SCRIPT"
  echo "###########################"
  echo ""

  # Create worktree if it doesn't exist
  if [ -d "$WORKTREE_PATH" ]; then
    echo "Worktree already exists at: $WORKTREE_PATH"
  else
    echo "Creating worktree at: $WORKTREE_PATH"
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"
    echo "Worktree created."
  fi

  # Validate ralph.sh exists
  if [ ! -f "$RALPH_SCRIPT" ]; then
    echo "Error: ralph.sh not found at $RALPH_SCRIPT" >&2
    exit 1
  fi

  echo ""
  echo "Launching ralph loop in worktree..."
  echo ""

  # Build ralph.sh arguments
  RALPH_ARGS=("--agent" "$AGENT" "--max-iterations" "$MAX_ITERATIONS")

  if [ -n "$PROVIDER" ]; then
    RALPH_ARGS+=("--provider" "$PROVIDER")
  fi

  if [ -n "$MODEL" ]; then
    RALPH_ARGS+=("--model" "$MODEL")
  fi

  if [ "$USE_TMUX" = true ]; then
    RALPH_ARGS+=("--tmux")
  fi

  if [ "$KEEP_TMUX" = true ]; then
    RALPH_ARGS+=("--keep-tmux")
  fi

  if [ -n "$IDLE_TIMEOUT" ]; then
    RALPH_ARGS+=("--idle-timeout" "$IDLE_TIMEOUT")
  fi

  RALPH_ARGS+=("$FEATURE_NAME")

  # Launch ralph.sh from the worktree directory
  cd "$WORKTREE_PATH"
  exec "$RALPH_SCRIPT" "${RALPH_ARGS[@]}"
fi
