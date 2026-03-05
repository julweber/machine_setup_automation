#!/bin/bash

# Spec Framework — Skill Linker
# Creates (or refreshes) agent skill symlinks in a target project directory.
#
# Usage: ./scripts/link-skills.sh <project-location>
#
# The script links every subdirectory found in <project-location>/skills/
# into each agent's skill discovery directory:
#   .pi/skills/
#   .claude/skills/
#   .opencode/skills/
#
# All symlinks are relative, idempotent, and safe to re-run at any time.
# This script does NOT copy skill files — it only links what is already
# present in <project-location>/skills/.

set -e

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <project-location>" >&2
  exit 1
fi

PROJECT_LOCATION="$1"

if [ ! -d "$PROJECT_LOCATION" ]; then
  echo "Error: Project directory '$PROJECT_LOCATION' does not exist." >&2
  exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_LOCATION" && pwd)"

# ---------------------------------------------------------------------------
# Pre-flight: skills/ must exist in the target project
# ---------------------------------------------------------------------------

SKILLS_DIR="$PROJECT_DIR/skills"

if [ ! -d "$SKILLS_DIR" ]; then
  echo "Error: No skills/ directory found at '$SKILLS_DIR'." >&2
  echo "       Run setup.sh first, or copy the skills directory manually." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Discover skills dynamically from project's skills/ subdirectories
# ---------------------------------------------------------------------------

mapfile -t SKILLS < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

if [ "${#SKILLS[@]}" -eq 0 ]; then
  echo "Error: No skill subdirectories found in '$SKILLS_DIR'." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Configuration summary
# ---------------------------------------------------------------------------

echo "Project dir:  $PROJECT_DIR"
echo "Skills dir:   $SKILLS_DIR"
echo "Skills found: ${SKILLS[*]}"
echo ""

# ---------------------------------------------------------------------------
# Helper: compute relative path via python3
# ---------------------------------------------------------------------------

rel_path() {
  local target="$1"
  local link_dir="$2"
  python3 -c "import os.path; print(os.path.relpath('$target', '$link_dir'))"
}

# ---------------------------------------------------------------------------
# Agent skill directories to populate
# ---------------------------------------------------------------------------

AGENT_DIRS=(
  ".pi/skills"
  ".claude/skills"
  ".opencode/skills"
)

# ---------------------------------------------------------------------------
# Create symlinks for each agent
# ---------------------------------------------------------------------------

for agent_dir in "${AGENT_DIRS[@]}"; do
  full_agent_dir="$PROJECT_DIR/$agent_dir"
  mkdir -p "$full_agent_dir"

  echo "Linking $agent_dir/..."
  for skill in "${SKILLS[@]}"; do
    link="$full_agent_dir/$skill"
    target="$SKILLS_DIR/$skill"
    rel="$(rel_path "$target" "$full_agent_dir")"
    ln -sfn "$rel" "$link"
    echo "  ✓ $agent_dir/$skill -> $rel"
  done
done

# ---------------------------------------------------------------------------
# Verification pass
# ---------------------------------------------------------------------------

echo ""
echo "Verifying symlinks..."

all_ok=true
for agent_dir in "${AGENT_DIRS[@]}"; do
  full_agent_dir="$PROJECT_DIR/$agent_dir"
  ok=0
  broken=0
  for skill in "${SKILLS[@]}"; do
    link="$full_agent_dir/$skill"
    if [ -e "$link" ]; then
      (( ok++ )) || true
    else
      echo "  ✗ BROKEN: $agent_dir/$skill" >&2
      (( broken++ )) || true
      all_ok=false
    fi
  done
  echo "  $agent_dir/  ${ok}/${#SKILLS[@]} OK"
done

echo ""
if [ "$all_ok" = true ]; then
  echo "Skill linking complete."
else
  echo "Warning: Some symlinks could not be verified. Check output above." >&2
  exit 1
fi
