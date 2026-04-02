---
name: spec-to-tasks
description: Converts reviewed feature specifications into atomic, dependency-ordered task lists (tasks.yaml) for the ralph loop. Use when a feature spec has passed review and is ready for implementation or when user says 'generate tasks', 'convert spec to tasks'.
---

# Skill: spec-to-tasks

You are a skilled technical planner converting a reviewed feature specification into a structured task list for the ralph loop.

## Overview

This skill accepts an optional `<feature-name>` parameter. If not provided, list subdirectories in `specification/features/` and ask the user to select one.

Read the project and feature specs, generate an atomic task list, present it for review, and write `tasks/<feature-name>/tasks.yaml` only on explicit YES confirmation.

---

## Setup

### Feature Name

If a feature name was provided as a parameter, use it. Otherwise:
1. List subdirectory names in `specification/features/`
2. Ask the user: "Which feature would you like to convert to tasks? [list the subdirectory names]"

### Read Context

1. Read all `specification/project/*.md` files:
   - `description.md`, `concepts.md`, `architecture.md`, `conventions.md`, `test-strategy.md`
2. Read all files in `specification/features/<feature-name>/`
3. Note the **actual markdown heading anchors** in each file — these will be used for `source` references in the task list.
4. Read `specification/project/lessons-learned.md` if it exists. Note any lessons relevant to this feature's domain (e.g., tool usage, patterns to follow/avoid, past gotchas).

### Spec Readiness Check

Before generating tasks, scan `behaviors.md` and `tests.md` for signs of incompleteness:
- Empty files or files containing only headings
- `TBD`, `TODO`, `FIXME`, `?` placeholder markers
- Open questions ("Should this...", "Not sure if...")

If any are found, warn the user: "⚠ Spec may not be review-ready: [list issues]. Consider running `spec review <feature-name>` first. Continue anyway? (YES/NO)"
Only proceed on YES.

---

## Task Generation

### Break Down Behaviors

Analyze the behaviors defined in `behaviors.md` and split them into atomic implementation tasks. Consider:
- One behavior may produce multiple tasks (e.g., data model setup, business logic, API endpoint, tests)
- Tasks should be small enough to implement and validate in a single agent iteration
- Each task must be independently testable

**Granularity guidelines:**
- A task should be implementable by reading 1–3 spec sections and modifying ≤5 files
- If drafting success criteria produces more than 6 items → split the task
- If a behavior requires both "create the data structure" and "use it in an endpoint", prefer splitting unless they're trivially coupled
- Prefer more small tasks over fewer large tasks — the ralph loop retries failed tasks, so smaller tasks mean cheaper retries

### TDD Pattern

If `tests.md` defines test suites that need to be written (i.e., test files don't exist yet), generate test-writing tasks first:

- Assign them the lowest priority numbers (1, 2, 3...) so they run first
- Set `dependsOn: []` — test-writing tasks have no prerequisites
- **Do NOT include** `"All existing tests continue to pass"` as the final success criterion for test-writing tasks. The newly written tests will fail by design since the implementation doesn't exist yet.
- The final success criterion for test-writing tasks must be: `"Test file passes shellcheck -s bash with no errors"`
- Include in `description`: _"This is a TDD task. Tests are expected to fail at this stage — the implementation does not exist yet. The quality gate requiring passing tests is DISABLED for this task."_

Implementation tasks that follow do include `"All existing tests continue to pass"` as their final criterion.

### Determine Dependencies

Analyze the feature specification to determine logical `dependsOn` relationships:
- Foundation tasks (database schema, base models) come before business logic
- Business logic comes before API endpoints
- API endpoints come before integration tests
- Group related tasks to minimize blocking chains

### Generate Task Fields

For each task, generate:

| Field | Requirement |
|-------|-------------|
| `id` | Format: `task-NNN` (zero-padded to 3 digits, starting at `task-001`) |
| `title` | Verb-first, ≤10 words (e.g., "Implement login endpoint") |
| `description` | 2–5 sentences, self-contained context so the agent can understand the task without reading other tasks |
| `source` | Array of verified heading anchors from the spec files (e.g., `"specification/features/<feature-name>/behaviors.md#behavior-name"`) |
| `priority` | Integer, lower = higher priority; assign based on dependency order |
| `dependsOn` | Array of task IDs that must have `status: "passed"` before this task can run |
| `successCriteria` | 3–6 concrete, verifiable criteria; the **last criterion must always be**: `"All existing tests continue to pass"` (except for TDD test-writing tasks — see TDD Pattern) |
| `status` | Always `"pending"` |
| `attempts` | Always `0` |
| `hints` | *(Optional)* Array of short implementation warnings, non-obvious requirements, or tool-specific notes. Populate from lessons-learned or spec footnotes. Omit if empty. |

**Source references:** Use only heading anchors that actually exist in the spec files. Convert heading text to anchor format: lowercase, spaces to hyphens, remove special characters (e.g., "## User Can Login" → `#user-can-login`).

**Hints guidance:** Add a `hints` entry whenever you encounter a specific tool requirement, flag, or gotcha while reading the spec or lessons-learned. Keep each hint to one sentence.

### Success Criteria Guidelines

Each criterion should be:
- Concrete and verifiable (not vague)
- Derivable from the spec without interpretation
- Testable by running code or inspecting output

Example good criteria:
- "POST /auth/login returns 200 with a signed JWT on valid credentials"
- "POST /auth/login returns 401 with an error message on invalid credentials"
- "JWT expiry matches the value configured in environment variables"
- "All existing tests continue to pass"

### Apply Lessons

For each task, check if any lessons from `lessons-learned.md` are directly relevant (same tool, pattern, or code area). If so:
- Add a concrete note to the task's `description` (1 sentence max)
- Or add it as a `hints` entry (see field table)

Do not add generic lessons that don't apply to the specific task.

---

## Present Summary

Before writing, present the task list summary to the user:

> "I've generated [N] tasks for `<feature-name>`. Here's the summary:
>
> [List each task with: ID, title, priority, dependsOn]
>
> Shall I write this to `tasks/<feature-name>/tasks.yaml`? Please reply YES to confirm."

---

## Write Output

On YES confirmation:
1. Create the directory `tasks/<feature-name>/` if it doesn't exist
2. Write `tasks/<feature-name>/tasks.yaml` with the following structure:

```yaml
featureName: <feature-name>
branchName: feat/<feature-name>
tasks:
  - id: "task-001"
    title: "..."
    description: "..."
    source:
      - "specification/features/<feature-name>/behaviors.md#behavior-anchor"
    priority: 1
    dependsOn: []
    successCriteria:
      - "..."
      - "All existing tests continue to pass"
    status: pending
    attempts: 0
    hints:  # optional — omit if empty
      - "Use shellcheck -s bash (not plain shellcheck)"
```

After writing, tell the user:
> "`tasks/<feature-name>/tasks.yaml` has been written. Please review the file and make any adjustments needed. You have to commit the final tasks file before running `spec implement <feature-name>` as this will be executed within a separate git worktree (in `<project-name>-feat-<feature-name>` sibling directory)."
