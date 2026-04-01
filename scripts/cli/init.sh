#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# spec-init.sh — Implement the `spec init` subcommand
#
# Usage (via bin/spec dispatcher):
#   spec init <project-name> [location] [options]
#   spec init --update [options]
#   spec init --interactive [options]
#
# The script locates itself inside the installed spec framework and uses
# BASH_SOURCE[0] to derive the framework root directory.
# ──────────────────────────────────────────────────────────────────────────────

set -e

# ── Framework location ────────────────────────────────────────────────────────

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Global flags (parsed in main) ───────────────────────────────────────────

UPDATE_MODE=false
INTERACTIVE_MODE=false
AGENT_LIST=""  # comma-separated list from --agent flag
FORCE_FLAG=false
NO_GIT_FLAG=false

# ── Supported agents (case-insensitive validation) ───────────────────────────

declare -a SUPPORTED_AGENTS=("opencode" "claude" "pi" "codex")

validate_agent() {
    local agent="$1"
    agent_lower=$(echo "$agent" | tr '[:upper:]' '[:lower:]')
    
    for supported in "${SUPPORTED_AGENTS[@]}"; do
        if [ "$agent_lower" = "$supported" ]; then
            return 0
        fi
    done
    
    echo "Error: Unknown agent '$agent'. Supported agents: opencode, claude, pi, codex" >&2
    return 1
}

parse_agent_list() {
    local input="$1"
    # Normalize to lowercase and split by comma
    local normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    
    IFS=',' read -ra agents <<< "$normalized"
    
    for agent in "${agents[@]}"; do
        agent=$(echo "$agent" | xargs)  # trim whitespace
        if [ -n "$agent" ]; then
            if ! validate_agent "$agent"; then
                exit 1
            fi
            echo "$agent"
        fi
    done
}

# ── Usage / Help ─────────────────────────────────────────────────────────────

print_usage() {
    cat <<'EOF'
Usage: spec init <project-name> [directory] [options]
       spec init --update [options]
       spec init --interactive [options]

Project initialization and framework installation for Spec Driven Development.

Arguments:
  project-name    Name of the project
  directory       Target directory for the project (default: ./<project-name>)
                  When provided, the directory is used directly as the project root
                  (no subdirectory with the project name is created inside it)

Options:
  --update                    Refresh framework in an existing project
  --interactive               Run guided wizard with prompts
  --agent <name>              Agent(s) to link: opencode, claude, pi, codex (comma-separated)
  --all-agents                Link all three agents (default for update mode)
  --force                     Bypass safety checks (e.g., existing content detection)
  --no-git                    Skip git initialization and staging
  -h, --help                  Show this help message

Examples:
  # Initialize a new project in ./my-project/
  spec init my-project

  # Initialize in a specific directory (uses it as project root)
  spec init my-project /path/to/my-project

  # Initialize spec-framework in an existing project directory
  spec init my-project ./existing-project

  # Interactive wizard mode
  spec init --interactive

  # Update existing project with specific agents
  spec init --update --agent opencode,claude,pi,codex

  # Force initialize (dangerous if content exists)
  spec init my-project --force

Modes:
  Init Mode (default): Creates new project structure and stages files for commit.
                       Requires project-name argument.
  
  Update Mode (--update): Refreshes all framework files in current directory.
                          Must be run from within an existing spec-framework project.
  
  Interactive Mode (--interactive): Prompts for all required information step-by-step.
                                    Useful for users who prefer guided setup.

What Gets Staged:
  - bin/spec (CLI binary)
  - scripts/ (all framework scripts and handlers)
  - scripts/ralph/* (ralph loop files)
  - skills/ (all skill definitions)
  - .pi/skills/, .claude/skills/, .opencode/skills/, .codex/skills/ (agent symlinks)

Safety:
  - Init mode checks for existing spec content and aborts to prevent data loss
  - Update mode validates project structure before proceeding
  - All changes are staged but not committed — review with 'git status' first
EOF
}

# ── Helper: write a placeholder spec file ────────────────────────────────────

write_placeholder() {
    local file="$1"
    local title="$2"
    local sections="$3"
    cat > "$file" <<EOF
# $title

<!-- Complete using /spec-project-brainstorm -->

$sections
EOF
}

# ── Helper: create relative symlinks for all agents (always recreate) ─────────

create_agent_symlinks() {
    local project_dir="$1"
    local skills_dir="${project_dir}/skills"

    if [ ! -d "$skills_dir" ]; then
        echo "Warning: skills/ directory not found at '${skills_dir}'" >&2
        return 1
    fi

    # Compute relative path from a link directory to a target directory
    rel_path() {
        local target="$1"
        local link_dir="$2"
        python3 -c "import os.path; print(os.path.relpath('$target', '$link_dir'))"
    }

    local agent_dirs=(".pi/skills" ".claude/skills" ".opencode/skills" ".codex/skills")
    local skills=()
    mapfile -t skills < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

    if [ "${#skills[@]}" -eq 0 ]; then
        echo "Warning: No skill subdirectories found in '${skills_dir}'" >&2
        return 0
    fi

    for agent_rel_dir in "${agent_dirs[@]}"; do
        local full_agent_dir="${project_dir}/${agent_rel_dir}"
        mkdir -p "$full_agent_dir"

        for skill in "${skills[@]}"; do
            local link="${full_agent_dir}/${skill}"
            local target="${skills_dir}/${skill}"
            local rel
            rel="$(rel_path "$target" "$full_agent_dir")"
            ln -sfn "$rel" "$link"
        done
    done
    
    echo "Agent symlinks created at: .pi/skills/, .claude/skills/, .opencode/skills/, .codex/skills/"
}

# ── Helper: create relative symlinks for specific agents only ────────────────

create_agent_symlinks_for() {
    local project_dir="$1"
    shift
    local agent_list=("$@")
    local skills_dir="${project_dir}/skills"

    if [ ! -d "$skills_dir" ]; then
        echo "Warning: skills/ directory not found at '${skills_dir}'" >&2
        return 1
    fi

    rel_path() {
        local target="$1"
        local link_dir="$2"
        python3 -c "import os.path; print(os.path.relpath('$target', '$link_dir'))"
    }

    # Populate skills array for this function
    local skills=()
    mapfile -t skills < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

    if [ "${#skills[@]}" -eq 0 ]; then
        echo "Warning: No skill subdirectories found in '${skills_dir}'" >&2
        return 0
    fi

    for agent in "${agent_list[@]}"; do
        case "$agent" in
            opencode) local agent_rel_dir=".opencode/skills" ;;
            claude)   local agent_rel_dir=".claude/skills" ;;
            pi)       local agent_rel_dir=".pi/skills" ;;
            codex)    local agent_rel_dir=".codex/skills" ;;
            *) echo "Error: Unknown agent '$agent' in symlink creation" >&2; continue ;;
        esac
        
        local full_agent_dir="${project_dir}/${agent_rel_dir}"
        mkdir -p "$full_agent_dir"

        for skill in "${skills[@]}"; do
            local link="${full_agent_dir}/${skill}"
            local target="${skills_dir}/${skill}"
            local rel
            rel="$(rel_path "$target" "$full_agent_dir")"
            ln -sfn "$rel" "$link"
        done
        
        echo "Symlinked for agent: $agent (${full_agent_dir})"
    done
    
    echo "Agent symlinks created successfully."
}

# ── Helper: validate init project (no existing non-placeholder content) ───────

check_existing_content() {
    local project_dir="$1"
    local spec_project_dir="${project_dir}/specification/project"
    
    local errors=()
    
    # Check each required spec file for non-placeholder content
    for file in description.md concepts.md architecture.md conventions.md test-strategy.md; do
        fpath="${spec_project_dir}/${file}"
        if [ -f "$fpath" ]; then
            # Count non-comment, non-header, non-empty lines
            local content_lines=$(grep -v '^<!--' "$fpath" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | wc -l)
            
            if [ "$content_lines" -gt 2 ]; then
                errors+=("  - ${spec_project_dir}/${file} (${content_lines} non-empty lines)")
            fi
        fi
    done
    
    if [ ${#errors[@]} -gt 0 ]; then
        echo "Error: Cannot initialize in directory containing existing spec content." >&2
        echo "" >&2
        echo "Found non-placeholder content in:" >&2
        for err in "${errors[@]}"; do
            echo "$err" >&2
        done
        echo "" >&2
        if [ "$FORCE_FLAG" = true ]; then
            echo "Using --force flag, proceeding anyway (risk of data loss)."
            return 0
        else
            echo "Use --force to override this safety check." >&2
            echo "Or remove/back up the existing spec files first." >&2
            return 1
        fi
    fi
    
    return 0
}

# ── Helper: validate update project (must be valid spec-framework project) ───

validate_update_project() {
    local project_dir="$1"
    
    # Check for required directories
    if [ ! -d "${project_dir}/scripts" ] || [ ! -d "${project_dir}/skills" ]; then
        echo "Error: Not a valid spec-framework project." >&2
        echo "No 'scripts/' or 'skills/' directory found at '${project_dir}'." >&2
        echo "" >&2
        echo "Run 'spec init <name> /path' to initialize a new project instead." >&2
        return 1
    fi
    
    # Check for git repository
    if [ ! -d "${project_dir}/.git" ]; then
        echo "Error: Not a valid spec-framework project." >&2
        echo "No git repository found at '${project_dir}'." >&2
        echo "" >&2
        echo "This does not look like an initialized spec-framework project." >&2
        return 1
    fi
    
    return 0
}

# ── Helper: stage framework files and print summary ───────────────────────────

stage_framework_files() {
    local project_dir="$1"
    
    if [ "$NO_GIT_FLAG" = true ]; then
        echo "Git staging skipped (--no-git flag)."
        return 0
    fi
    
    # Initialize git repo if needed (init mode only)
    if [ ! -d "${project_dir}/.git" ]; then
        echo "Initializing git repository..."
        git init -q -C "$project_dir"
    fi
    
    # Stage all spec-framework files
    echo "" >&2
    echo "Staging framework files..." >&2
    
    local staged_files=()
    
    # Always stage bin/spec and scripts/ (use --all to include untracked files)
    git -C "$project_dir" add --all bin/spec 2>/dev/null || true
    git -C "$project_dir" add --all scripts/ 2>/dev/null && \
        staged_files+=("bin/spec, scripts/")
    
    # Stage ralph files (use --all to include untracked)
    git -C "$project_dir" add --all scripts/ralph/ 2>/dev/null
    
    # Stage skills directory (use --all to include untracked)
    git -C "$project_dir" add --all skills/ 2>/dev/null && \
        staged_files+=("skills/")
    
    # Stage agent symlinks (they're directories, so we need to handle them specially)
    for agent_link in ".pi/skills" ".claude/skills" ".opencode/skills" ".codex/skills"; do
        if [ -L "${project_dir}/${agent_link}" ]; then
            staged_files+=("${agent_link}/")
        fi
    done
    
    # Stage .gitignore if exists (use --all to include untracked)
    git -C "$project_dir" add --all .gitignore 2>/dev/null && \
        staged_files+=(".gitignore")
    
    # Print summary
    echo "" >&2
    echo "Files staged for commit:" >&2
    if [ ${#staged_files[@]} -eq 0 ]; then
        echo "  (no changes to stage)" >&2
    else
        for file in "${staged_files[@]}"; do
            echo "  - $file" >&2
        done
    fi
    
    echo "" >&2
    echo "Review changes with: git -C '$project_dir' status" >&2
    echo "" >&2
}

# ── UPDATE MODE ───────────────────────────────────────────────────────────────

cmd_update() {
    local provided_dir="${1:-}"
    local project_dir

    if [ -n "$provided_dir" ]; then
        if [ ! -d "$provided_dir" ]; then
            echo "Error: Directory '${provided_dir}' does not exist." >&2
            exit 1
        fi
        project_dir="$(cd "$provided_dir" && pwd)"
    else
        project_dir="$(pwd)"
    fi
    
    # Validate project structure
    if ! validate_update_project "$project_dir"; then
        exit 1
    fi
    
    echo "Updating spec framework in: ${project_dir}"
    echo ""
    
    # Determine which agents to link
    local agents_to_link=()
    
    if [ -n "$AGENT_LIST" ]; then
        # Parse --agent flag (already validated)
        while IFS= read -r agent; do
            if [ -n "$agent" ]; then
                agents_to_link+=("$agent")
            fi
        done < <(parse_agent_list "$AGENT_LIST")
    else
        # Interactive prompt for update mode
        echo "Which agents to link?" >&2
        echo "  Options: opencode, claude, pi, codex (comma-separated)" >&2
        echo "  Default: all three agents" >&2
        read -r -p "> " user_input
        
        case "$(echo "$user_input" | tr '[:upper:]' '[:lower:]')" in
            opencode|o)  agents_to_link=("opencode") ;;
            claude|c)    agents_to_link=("claude") ;;
            pi|p)        agents_to_link=("pi") ;;
            codex|co)    agents_to_link=("codex") ;;
            all|"")      agents_to_link=("opencode" "claude" "pi" "codex") ;;
            *) 
                echo "Invalid input, using default: all three agents" >&2
                agents_to_link=("opencode" "claude" "pi" "codex")
                ;;
        esac
    fi
    
    # Validate agent list before proceeding
    if [ ${#agents_to_link[@]} -eq 0 ]; then
        echo "Error: No valid agents specified." >&2
        exit 1
    fi
    
    echo "" >&2
    echo "Agents to link: ${agents_to_link[*]}" >&2
    echo ""
    
    # Refresh Ralph loop files
    echo "Copying ralph loop files..."
    mkdir -p "${project_dir}/scripts/ralph"
    cp -r "${FRAMEWORK_DIR}/scripts/ralph/." "${project_dir}/scripts/ralph/" || true
    chmod +x "${project_dir}"/scripts/ralph/*.sh
    
    # Refresh scripts
    echo "Copying framework scripts..."
    cp -f "${FRAMEWORK_DIR}/scripts"/*.sh "${project_dir}/scripts/" || true
    chmod +x "${project_dir}"/scripts/*.sh

    # Refresh spec cli
    echo "Copying spec cli ..."
    mkdir -p "${project_dir}/bin"
    mkdir -p "${project_dir}/scripts/cli"
    cp -f "${FRAMEWORK_DIR}/bin/spec" "${project_dir}/bin/spec" || true
    cp -f "${FRAMEWORK_DIR}/scripts/cli"/*.sh "${project_dir}/scripts/cli"/ || true
    chmod +x "${project_dir}/bin/spec"
    
    # Refresh skills directory (replace entirely)
    echo "Refreshing skills directory..."
    # When FRAMEWORK_DIR == project_dir, use cp -a to handle in-place replacement
    if [ "${FRAMEWORK_DIR}" = "${project_dir}" ]; then
        cp -a "${FRAMEWORK_DIR}/skills/*" "${project_dir}/.skills-temp" || true
        mv "${project_dir}/.skills-temp" "${project_dir}/skills" || true
    else
        cp -r "${FRAMEWORK_DIR}/skills/*" "${project_dir}/skills/" || true
    fi
    
    # Recreate agent symlinks for specified agents only
    echo "" >&2
    echo "Creating agent skill symlinks..." >&2
    create_agent_symlinks_for "$project_dir" "${agents_to_link[@]}"
    
    # Stage changes (no commit)
    stage_framework_files "$project_dir"
    
    echo "" >&2
    echo "==========================================" >&2
    echo "Update complete." >&2
    echo "Project directory: ${project_dir}" >&2
    echo "Agents linked: ${agents_to_link[*]}" >&2
    echo "==========================================" >&2
    echo "" >&2
}

# ── INIT MODE (default) ───────────────────────────────────────────────────────

cmd_init() {
    local project_name="$1"
    local directory="${2:-}"
    
    # Determine project directory:
    # - If a directory argument is provided, use it directly as the project root
    # - Otherwise, create ./<project-name>
    local project_dir
    if [ -n "$directory" ]; then
        # Use provided directory directly (don't create a subdirectory)
        if [ ! -d "$directory" ]; then
            mkdir -p "$directory" || {
                echo "Error: Cannot create directory '${directory}'." >&2
                exit 1
            }
        fi
        project_dir="$(cd "$directory" && pwd)"
    else
        project_dir="$(pwd)/${project_name}"
    fi
    
    # Safety check: existing content detection (BEFORE any modifications)
    echo "Checking for existing spec content..." >&2
    if ! check_existing_content "$project_dir"; then
        exit 1
    fi
    
    echo "Initializing project '${project_name}'..." >&2
    echo "Project directory: ${project_dir}" >&2
    echo "" >&2
    
    # Create directory structure (only after safety checks pass)
    echo "Creating directory structure..." >&2
    mkdir -p "${project_dir}/specification/project"
    mkdir -p "${project_dir}/specification/features"
    mkdir -p "${project_dir}/tasks"
    mkdir -p "${project_dir}/scripts/ralph"
    mkdir -p "${project_dir}/skills"
    
    # Write placeholder spec files
    echo "Writing specification/project placeholder files..." >&2
    
    write_placeholder "${project_dir}/specification/project/description.md" \
        "Project Description" \
        "## What It Does

## Problem It Solves

## Primary Users

## Core Capabilities

## Out of Scope"

    write_placeholder "${project_dir}/specification/project/concepts.md" \
        "Domain Concepts" \
        "## Key Entities

## Terminology

## Relationships"

    write_placeholder "${project_dir}/specification/project/architecture.md" \
        "Architecture" \
        "## Tech Stack

## System Structure

## Components

## External Integrations

## Deployment"

    write_placeholder "${project_dir}/specification/project/conventions.md" \
        "Conventions" \
        "## Code Style

## Naming Conventions

## Architectural Patterns

## Libraries and Utilities

## Anti-Patterns"

    write_placeholder "${project_dir}/specification/project/test-strategy.md" \
        "Test Strategy" \
        "## Test Types

## What Gets Tested

## Coverage Expectations

## Frameworks and Tools

## Quality Check Definition"
    
    # Copy framework files
    echo "Copying ralph loop files..." >&2
    mkdir -p "${project_dir}/scripts/ralph"
    cp -r "${FRAMEWORK_DIR}/scripts/ralph/." "${project_dir}/scripts/ralph/"
    chmod +x "${project_dir}"/scripts/ralph/*.sh

    echo "Copying framework scripts..." >&2
    cp -f "${FRAMEWORK_DIR}/scripts"/*.sh "${project_dir}/scripts/"
    chmod +x "${project_dir}"/scripts/*.sh

    echo "Copying spec CLI..." >&2
    mkdir -p "${project_dir}/bin"
    mkdir -p "${project_dir}/scripts/cli"
    cp -f "${FRAMEWORK_DIR}/bin/spec" "${project_dir}/bin/spec"
    cp -f "${FRAMEWORK_DIR}/scripts/cli"/*.sh "${project_dir}/scripts/cli/"
    chmod +x "${project_dir}/bin/spec"

    echo "Copying skills directory..." >&2
    cp -r "${FRAMEWORK_DIR}/skills/." "${project_dir}/skills/"

    # Create agent skill symlinks (all three by default in init mode)
    echo "" >&2
    echo "Creating agent skill symlinks..." >&2
    create_agent_symlinks "$project_dir"

    # Initialize git repository if needed (skipped with --no-git)
    if [ "$NO_GIT_FLAG" = true ]; then
        echo "Git initialization skipped (--no-git flag)." >&2
    elif [ ! -d "${project_dir}/.git" ]; then
        echo "Initializing git repository (if needed)..." >&2
        git init -q "$project_dir"
        echo "Git repository initialized." >&2
    else
        echo "Git repository already exists — skipping init." >&2
    fi
    
    # Copy .gitignore template if it exists and not present
    local gitignore_template="${FRAMEWORK_DIR}/templates/.gitignore.template"
    if [ ! -f "${project_dir}/.gitignore" ] && [ -f "$gitignore_template" ]; then
        cp "$gitignore_template" "${project_dir}/.gitignore"
        echo "Copied .gitignore template." >&2
    fi
    
    # Stage framework files (no auto-commit)
    stage_framework_files "$project_dir"

    # Success message
    echo "" >&2
    echo "==========================================" >&2
    echo "Setup complete! Project initialized successfully." >&2
    echo "Project name:      ${project_name}" >&2
    echo "Project directory: ${project_dir}" >&2
    echo "==========================================" >&2
    echo "" >&2
    echo "Next steps:" >&2
    echo "  1. Open an agent session in ${project_dir}" >&2
    echo "  2. Run /spec-project-brainstorm to define your project spec" >&2
    echo "  3. Run /spec-feature-brainstorm <feature-name> to define a feature" >&2
    echo "  4. Run /spec-review <feature-name> to review and finalize the spec" >&2
    echo "  5. Run /spec-to-tasks <feature-name> to generate the task list" >&2
    echo "  6. git commit the specification and tasks.yaml" >&2
    echo "  7. Run spec implement <feature-name> to start implementation" >&2
    echo "" >&2
}

# ── INTERACTIVE MODE (guided wizard) ─────────────────────────────────────────

cmd_interactive() {
    echo "==========================================" >&2
    echo "Spec Framework Initialization Wizard" >&2
    echo "==========================================" >&2
    echo "" >&2
    
    # Prompt 1: Project name (required)
    read -r -p "Project name: " project_name
    if [ -z "$project_name" ]; then
        echo "Error: Project name is required." >&2
        exit 1
    fi
    
    # Prompt 2: Project directory
    local default_dir="./${project_name}"
    read -r -p "Project directory (press Enter for ${default_dir}): " dir_input
    if [ -z "$dir_input" ]; then
        directory=""  # will use default ./<project-name> in cmd_init
    else
        directory="$dir_input"
    fi
    
    # Resolve the target directory for display and existence check
    local target_dir
    if [ -n "$directory" ]; then
        target_dir="$directory"
    else
        target_dir="./${project_name}"
    fi
    
    # Check if the target directory already exists and has content
    if [ -d "$target_dir" ]; then
        local file_count
        file_count="$(find "$target_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
        
        if [ "$file_count" -gt 0 ]; then
            echo "" >&2
            echo "Directory '${target_dir}' already exists and is not empty." >&2
            echo "It contains ${file_count} file(s)/directory(ies)." >&2
            read -r -p "Initialize spec-framework in this existing project? [y/N]: " use_existing
            
            if ! [[ "$use_existing" =~ ^[Yy]$ ]]; then
                echo "Initialization cancelled." >&2
                exit 0
            fi
            echo "" >&2
        fi
    fi
    
    # Prompt 3: Agent selection
    echo "" >&2
    echo "Which agents to link?" >&2
    echo "  Options: opencode, claude, pi, codex (comma-separated)" >&2
    echo "  Default: all three agents" >&2
    read -r -p "> " agent_input
    
    local agents_to_link=()
    case "$(echo "$agent_input" | tr '[:upper:]' '[:lower:]')" in
        opencode|o)  agents_to_link=("opencode") ;;
        claude|c)    agents_to_link=("claude") ;;
        pi|p)        agents_to_link=("pi") ;;
        codex|co)    agents_to_link=("codex") ;;
        all|"")      agents_to_link=("opencode" "claude" "pi" "codex") ;;
        *) 
            echo "Invalid input, using default: all three agents" >&2
            agents_to_link=("opencode" "claude" "pi" "codex")
            ;;
    esac
    
    # Resolve absolute path for display
    local display_dir
    if [ -n "$directory" ]; then
        if [ -d "$directory" ]; then
            display_dir="$(cd "$directory" && pwd)"
        else
            display_dir="$(cd "$(dirname "$directory")" 2>/dev/null && pwd)/$(basename "$directory")"
        fi
    else
        display_dir="$(pwd)/${project_name}"
    fi
    
    # Prompt 4: Confirmation before staging
    echo "" >&2
    echo "Summary:" >&2
    echo "  Project name: ${project_name}" >&2
    echo "  Directory:    ${display_dir}" >&2
    echo "  Agents:       ${agents_to_link[*]}" >&2
    read -r -p "Continue? [y/N]: " confirm
    
    if ! [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Initialization cancelled." >&2
        exit 0
    fi
    
    # Run init mode with gathered parameters
    if [ -n "$directory" ]; then
        cmd_init "$project_name" "$directory"
    else
        cmd_init "$project_name"
    fi
    
    # Update symlinks for specific agents (init creates all three by default)
    if [ ${#agents_to_link[@]} -lt 3 ]; then
        local resolved_project_dir="$display_dir"
        echo "" >&2
        echo "Updating agent symlinks to use only: ${agents_to_link[*]}" >&2
        create_agent_symlinks_for "$resolved_project_dir" "${agents_to_link[@]}"
        
        # Re-stage the symlink changes
        stage_framework_files "$resolved_project_dir"
    fi
}

# ── Main Entry Point ───────────────────────────────────────────────────────────

main() {
    # Help flag (check first)
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        print_usage
        exit 0
    fi

    # Two-pass argument parsing: separate flags from positional arguments so
    # flags can appear anywhere on the command line (before or after positionals).
    local positionals=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --update)
                UPDATE_MODE=true
                shift
                ;;
            --interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            --agent)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    echo "Error: --agent requires an argument (e.g., pi,opencode,claude)" >&2
                    exit 1
                fi
                AGENT_LIST="$2"
                shift 2
                ;;
            --all-agents)
                AGENT_LIST="opencode,claude,pi,codex"
                shift
                ;;
            --force)
                FORCE_FLAG=true
                shift
                ;;
            --no-git)
                NO_GIT_FLAG=true
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            --)
                shift
                # Everything after -- is a positional
                while [ $# -gt 0 ]; do
                    positionals+=("$1")
                    shift
                done
                ;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                print_usage
                exit 1
                ;;
            *)
                # Positional argument
                positionals+=("$1")
                shift
                ;;
        esac
    done

    # Restore positionals into $@
    set -- "${positionals[@]+"${positionals[@]}"}"

    # Validate mutually exclusive modes
    if [ "$UPDATE_MODE" = true ] && [ "$INTERACTIVE_MODE" = true ]; then
        echo "Error: --update and --interactive are mutually exclusive." >&2
        exit 1
    fi
    
    # Branch based on mode
    if [ "$UPDATE_MODE" = true ]; then
        # Positional args for update:
        #   spec init --update [<project-name>] [<directory>]
        # When two positionals: $1=project-name (ignored), $2=directory
        # When one positional:  $1=directory (or project-name — try it as a path)
        # When zero:            use cwd
        local update_dir=""
        if [ $# -ge 2 ]; then
            update_dir="${2}"
        elif [ $# -eq 1 ]; then
            update_dir="${1}"
        fi
        cmd_update "$update_dir"
        
    elif [ "$INTERACTIVE_MODE" = true ]; then
        cmd_interactive
        
    else
        # Default: Init mode (requires project-name argument)
        if [ $# -eq 0 ]; then
            echo "Error: Missing required argument: project-name" >&2
            print_usage
            exit 1
        fi
        
        local project_name="$1"
        local directory="${2:-}"
        
        if [ -n "$directory" ]; then
            cmd_init "$project_name" "$directory"
        else
            cmd_init "$project_name"
        fi
    fi
    
    exit 0
}

main "$@"
