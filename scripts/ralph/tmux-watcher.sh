#!/usr/bin/env bash
# tmux-watcher.sh - Polls tmux capture-pane for ralph signal detection
# Usage: tmux-watcher.sh <tmux-target> <signal-file> [idle-timeout-seconds]
#
# Monitors a tmux pane for ralph completion signals by periodically
# capturing pane content and scanning for signal patterns.
# Handles both --print mode (XML tags) and TUI mode (plain text) output.
#
# Writes one of these to signal-file on detection:
#   COMPLETE | SUB-TASK-COMPLETE | FAILED | IDLE | PANE_CLOSED

set -euo pipefail

TARGET="$1"
SIGNAL_FILE="$2"
IDLE_TIMEOUT="${3:-120}"
POLL_INTERVAL=1

LAST_CONTENT=""
LAST_CHANGE=$(date +%s)

rm -f "$SIGNAL_FILE"

detect_signal() {
  local content="$1"
  # Check COMPLETE before SUB-TASK-COMPLETE to avoid false positives
  # (SUB-TASK-COMPLETE contains COMPLETE)
  if echo "$content" | grep -qE '<promise>SUB-TASK-COMPLETE</promise>|● SUB-TASK-COMPLETE'; then
    echo "SUB-TASK-COMPLETE"
  elif echo "$content" | grep -qE '<promise>COMPLETE</promise>|● COMPLETE'; then
    echo "COMPLETE"
  elif echo "$content" | grep -qE '<promise>FAILED</promise>|● FAILED'; then
    echo "FAILED"
  fi
}

while true; do
  CONTENT=$(tmux capture-pane -t "$TARGET" -p -S -500 2>/dev/null) || break
  NOW=$(date +%s)

  SIGNAL=$(detect_signal "$CONTENT")
  if [ -n "$SIGNAL" ]; then
    echo "$SIGNAL" > "$SIGNAL_FILE"
    exit 0
  fi

  if [ "$CONTENT" != "$LAST_CONTENT" ]; then
    LAST_CONTENT="$CONTENT"
    LAST_CHANGE=$NOW
  fi

  IDLE_SECS=$((NOW - LAST_CHANGE))
  if [ "$IDLE_SECS" -ge "$IDLE_TIMEOUT" ]; then
    echo "IDLE" > "$SIGNAL_FILE"
    exit 0
  fi

  sleep "$POLL_INTERVAL"
done

echo "PANE_CLOSED" > "$SIGNAL_FILE"
