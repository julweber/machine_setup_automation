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

---

## Task Generation

### Break Down Behaviors

Analyze the behaviors defined in `behaviors.md` and split them into atomic implementation tasks. Consider:
- One behavior may produce multiple tasks (e.g., data model setup, business logic, API endpoint, tests)
- Tasks should be small enough to implement and validate in a single agent iteration
- Each task must be independently testable

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
| `successCriteria` | 3–6 concrete, verifiable criteria; the **last criterion must always be**: `"All existing tests continue to pass"` |
| `status` | Always `"pending"` |
| `attempts` | Always `0` |

**Source references:** Use only heading anchors that actually exist in the spec files. Convert heading text to anchor format: lowercase, spaces to hyphens, remove special characters (e.g., "## User Can Login" → `#user-can-login`).

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
```

After writing, tell the user:
> "`tasks/<feature-name>/tasks.yaml` has been written. Please review the file and make any adjustments needed. You have to commit the final tasks file before running `./scripts/implement-feature.sh <feature-name>` as this will be executed within a separate git worktree (in `<project-name>-feat-<feature-name>` sibling directory)."

## Priority order

If the feature you are working on contains tasks for writing testsuites:
  - Prioritize them at the beginning of the feature implentation
  - Add additional instructions that the testsuite is implemented first, so that the testsuite is expected to fail initially
  - a test implementation task is considered complete without a green testsuite!!!