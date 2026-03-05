#!/usr/bin/env bash
# session-monitor.sh - Monitor session progress from a JSONL session file
# Usage: ./session-monitor.sh <session_file>
# Press 'q' or Ctrl+C to stop

set -euo pipefail

# ── Argument handling ──────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <session_file>" >&2
    exit 1
fi

SESSION_FILE="$1"

if [[ ! -f "$SESSION_FILE" ]]; then
    echo "Error: File not found: $SESSION_FILE" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# ── Colour helpers ─────────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
YELLOW="\033[33m"
GREEN="\033[32m"
MAGENTA="\033[35m"
RED="\033[31m"
BLUE="\033[34m"

# ── Cleanup on exit ────────────────────────────────────────────────────────────
cleanup() {
    tput cnorm 2>/dev/null || true   # restore cursor
    echo -e "\n${DIM}Monitor stopped.${RESET}"
    exit 0
}
trap cleanup INT TERM

# ── Extract a human-readable event text from a single JSON line ────────────────
parse_event() {
    local line="$1"

    # Validate that it's JSON
    if ! echo "$line" | jq -e . &>/dev/null; then
        return
    fi

    local type timestamp color text

    type=$(echo "$line"      | jq -r '.type // "unknown"')
    timestamp=$(echo "$line" | jq -r '.timestamp // ""')

    # Shorten timestamp: remove the trailing milliseconds+Z, keep readable part
    local ts_short
    ts_short=$(echo "$timestamp" | sed 's/\.[0-9]*Z$//; s/T/ /')

    case "$type" in
        session)
            color="$CYAN"
            local version id cwd
            version=$(echo "$line" | jq -r '.version // ""')
            id=$(echo "$line"      | jq -r '.id // ""')
            cwd=$(echo "$line"     | jq -r '.cwd // ""')
            text="SESSION START  version=$version  id=${id:0:8}…  cwd=$cwd"
            ;;
        model_change)
            color="$MAGENTA"
            local provider modelId
            provider=$(echo "$line" | jq -r '.provider // ""')
            modelId=$(echo "$line"  | jq -r '.modelId // ""')
            text="MODEL CHANGE   provider=$provider  model=$modelId"
            ;;
        thinking_level_change)
            color="$BLUE"
            local level
            level=$(echo "$line" | jq -r '.thinkingLevel // ""')
            text="THINKING LEVEL  →  $level"
            ;;
        message)
            local role content_type content_text tool_name
            role=$(echo "$line"         | jq -r '.message.role // "?"')
            # First content block
            content_type=$(echo "$line" | jq -r '.message.content[0].type // ""')

            case "$content_type" in
                text)
                    content_text=$(echo "$line" \
                        | jq -r '.message.content[0].text // ""' \
                        | head -c 120 | tr '\n' ' ')
                    color="$GREEN"
                    text="MSG [$role/text]     ${content_text}…"
                    ;;
                toolCall)
                    tool_name=$(echo "$line" | jq -r '.message.content[0].name // ""')
                    local tool_arg_summary
                    tool_arg_summary=$(echo "$line" \
                        | jq -r '(.message.content[0].arguments // {}) | to_entries | map("\(.key)=\(.value | tostring | .[0:40])") | join(", ")' \
                        2>/dev/null | head -c 120)
                    color="$YELLOW"
                    text="MSG [$role/toolCall] ${tool_name}($tool_arg_summary)"
                    ;;
                toolResult)
                    local result_text
                    result_text=$(echo "$line" \
                        | jq -r '.message.content[0].content[0].text // ""' \
                        | head -c 120 | tr '\n' ' ')
                    local is_error
                    is_error=$(echo "$line" | jq -r '.message.isError // false')
                    if [[ "$is_error" == "true" ]]; then
                        color="$RED"
                        text="MSG [$role/toolResult] ❌ ${result_text}…"
                    else
                        color="$GREEN"
                        text="MSG [$role/toolResult] ✔  ${result_text}…"
                    fi
                    ;;
                *)
                    color="$RESET"
                    text="MSG [$role/$content_type]"
                    ;;
            esac
            ;;
        *)
            color="$DIM"
            text="EVENT [$type]"
            ;;
    esac

    printf "${DIM}%s${RESET}  ${BOLD}${color}%s${RESET}\n" "$ts_short" "$text"
}

# ── Main loop ─────────────────────────────────────────────────────────────────
tput civis 2>/dev/null || true   # hide cursor for cleaner output

echo -e "${BOLD}${CYAN}Session monitor${RESET} — watching: ${BOLD}$SESSION_FILE${RESET}"
echo -e "${DIM}Press 'q' to quit, Ctrl+C to stop.${RESET}\n"

last_line=0

# Set terminal to raw mode so we can read single keypresses
# (only when attached to a terminal)
if [[ -t 0 ]]; then
    old_tty=$(stty -g)
    stty -echo -icanon min 0 time 1
fi

restore_tty() {
    if [[ -t 0 ]]; then
        stty "$old_tty" 2>/dev/null || true
    fi
    cleanup
}
trap restore_tty INT TERM

while true; do
    # Check for 'q' keypress (non-blocking)
    if [[ -t 0 ]]; then
        key=$(dd bs=1 count=1 2>/dev/null | cat)
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            restore_tty
            exit 0
        fi
    fi

    # Read any new lines appended to the file since last check
    current_lines=$(wc -l < "$SESSION_FILE")
    if (( current_lines > last_line )); then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            parse_event "$line"
        done < <(tail -n +"$((last_line + 1))" "$SESSION_FILE")
        last_line=$current_lines
    fi

    sleep 0.3
done