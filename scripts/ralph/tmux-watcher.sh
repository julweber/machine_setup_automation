#!/usr/bin/env bash
# tmux-watcher.sh - Monitors a tmux pane for ralph signal file or pane-closed state
# Usage: tmux-watcher.sh <tmux-target> <signal-file>
#
# Primary detection: polls <signal-file> written directly by the agent.
# Fallback detection: writes PANE_CLOSED to <signal-file> when the pane disappears.
#
# Signal file content (written by agent):   COMPLETE | SUB-TASK-COMPLETE | FAILED
# Signal file content (written by watcher): PANE_CLOSED

set -euo pipefail

TARGET="$1"
SIGNAL_FILE="$2"
POLL_INTERVAL=1

while true; do
  # Primary: agent wrote the signal file — our job is done
  if [ -f "$SIGNAL_FILE" ]; then
    exit 0
  fi

  # Fallback: pane disappeared — write PANE_CLOSED if agent hasn't signalled yet
  tmux capture-pane -t "$TARGET" -p >/dev/null 2>&1 || {
    [ ! -f "$SIGNAL_FILE" ] && echo "PANE_CLOSED" > "$SIGNAL_FILE"
    exit 0
  }

  sleep "$POLL_INTERVAL"
done
