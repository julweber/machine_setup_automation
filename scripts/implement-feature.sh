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
PROVIDER=""
MODEL=""

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
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--agent <agent>] [--max-iterations <n>] [--provider <provider>] [--model <model>] <feature-name>" >&2
      exit 1
      ;;
    *)
      FEATURE_NAME="$1"
      shift
      ;;
  esac
done

# Validate feature name
if [ -z "$FEATURE_NAME" ]; then
  echo "Error: feature-name is required" >&2
  echo "Usage: $0 [--agent <agent>] [--max-iterations <n>] <feature-name>" >&2
  exit 1
fi

# Validate agent
case "$AGENT" in
  opencode|claude|pi) ;;
  *)
    echo "Error: unknown agent '$AGENT'. Valid options: opencode, claude, pi" >&2
    exit 1
    ;;
esac

# Validate tasks file
TASKS_FILE="$PROJECT_ROOT/tasks/$FEATURE_NAME/tasks.yaml"
if [ ! -f "$TASKS_FILE" ]; then
  echo "Error: tasks file not found: $TASKS_FILE" >&2
  echo "Run /spec-to-tasks $FEATURE_NAME within your coding agent first to generate the task list." >&2
  exit 1
fi

# Validate yq is available
if ! command -v yq &>/dev/null; then
  echo "Error: 'yq' is required but not installed. Please install yq." >&2
  exit 1
fi

# Derive project name and paths
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
BRANCH_NAME="feat/$FEATURE_NAME"
WORKTREE_PATH="$(cd "$PROJECT_ROOT/.." && pwd)/${PROJECT_NAME}-feat-${FEATURE_NAME}"

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

RALPH_SCRIPT="$WORKTREE_PATH/scripts/ralph/ralph.sh"

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

# Only pass --provider if specified (ralph.sh will use it for pi agent)
if [ -n "$PROVIDER" ]; then
  RALPH_ARGS+=("--provider" "$PROVIDER")
fi

if [ -n "$MODEL" ]; then
  RALPH_ARGS+=("--model" "$MODEL")
fi

RALPH_ARGS+=("$FEATURE_NAME")

# Launch ralph.sh from the worktree directory
cd "$WORKTREE_PATH"
exec "$RALPH_SCRIPT" "${RALPH_ARGS[@]}"
