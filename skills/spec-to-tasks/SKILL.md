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
2. If `specification/project/lessons-learned.md` exists, read it and keep it in mind during task generation (used for `hints`).
3. Read all files in `specification/features/<feature-name>/`
4. Note the **actual markdown heading anchors** in each file — these will be used for `source` references in the task list.

---

## Task Generation

### Break Down Behaviors

Analyze the behaviors defined in `behaviors.md` and split them into atomic implementation tasks. Consider:
- One behavior may produce multiple tasks (e.g., data model setup, business logic, API endpoint, tests)
- Tasks should be small enough to implement and validate in a single agent iteration
- Each task must be independently testable

### Determine Dependencies

Use the following canonical dependency chain as a starting point, applying only the stages relevant to the feature:

```
test-suite tasks → schema/models → validation → business logic → API handlers → integration tests
```

Rules:
- **Test suite tasks always have `dependsOn: []`** — they run first with no prerequisites
- **Refactoring tasks depend on the implementation tasks they refactor** — never the reverse
- Tasks with no dependency between them can run in parallel; leave `dependsOn` empty for those
- If a circular dependency appears: extract a shared foundation task that both can depend on

### Generate Task Fields

For each task, generate:

| Field             | Requirement                                                                                                                        |
| -------------------| ------------------------------------------------------------------------------------------------------------------------------------|
| `id`              | Format: `task-NNN` (zero-padded to 3 digits, starting at `task-001`)                                                               |
| `title`           | Verb-first, ≤10 words (e.g., "Implement login endpoint")                                                                           |
| `description`     | 2–5 sentences; see guidance below                                                                                                  |
| `source`          | Array of verified heading anchors from the spec files (e.g., `"specification/features/<feature-name>/behaviors.md#behavior-name"`) |
| `priority`        | Integer, lower = higher priority; assign based on dependency order                                                                 |
| `dependsOn`       | Array of task IDs that must have `status: "passed"` before this task can run                                                       |
| `successCriteria` | 3–6 concrete, verifiable criteria; see guidance below                                                                              |
| `hints`           | Optional array of strings; include only when relevant lessons from `lessons-learned.md` apply                                      |
| `status`          | Always `"pending"`                                                                                                                 |
| `attempts`        | Always `0`                                                                                                                         |

**Source references:** Use only heading anchors that actually exist in the spec files. Convert heading text to anchor format: lowercase, spaces to hyphens, remove special characters (e.g., "## User Can Login" → `#user-can-login`).

### Writing Task Descriptions

Each description must be self-contained: an agent implementing this task should not need to read any other task to understand what to do. Include all of the following that apply:

- **What to implement** — the specific behavior or change, in concrete terms
- **Where** — exact file paths derived from project conventions (e.g., `scripts/spec-init-cmd.sh`, `tests/test-init.sh`)
- **What patterns to follow** — reference `conventions.md` or `architecture.md` explicitly where relevant (e.g., "use the subcommand-per-file dispatch pattern", "follow the `mapfile -t` array construction pattern")
- **What NOT to do** — call out applicable anti-patterns (e.g., "do not use `arr=($(cmd))`", "do not run the test suite")
- **TDD tasks** — always include verbatim: "This is a TDD task — the implementation does not exist yet, so all tests are expected to fail. Do NOT run the test suite against production code. The quality gate requiring passing tests is DISABLED for this task."

### Success Criteria Guidelines

Each criterion must be concrete, verifiable, and derivable from the spec without interpretation. The **last criterion must always be**: `"All existing tests continue to pass"` (except TDD test-suite tasks where the quality gate is disabled).

**By task type:**

- **TDD test-suite tasks:**
  - `"<test-file> exists and covers all test cases listed in <spec-anchor>"`
  - `"shellcheck -s bash <test-file> reports no errors"`
  - `"The test suite can be invoked without crashing (exits 0 regardless of test results)"`
  - `"Tests are expected to fail at this stage — a failing test suite is acceptable and expected"`
  - `"The quality gate requiring all tests to pass is DISABLED for this task"`

- **Implementation tasks:**
  - Verify the happy path with a concrete expected value (e.g., `"POST /auth/login returns 200 with a signed JWT on valid credentials"`)
  - Verify at least one error/edge case (e.g., `"POST /auth/login returns 401 with 'Invalid credentials' on wrong password"`)
  - Verify the file or function exists at the expected path
  - `"shellcheck -s bash <file> reports no errors"` for bash scripts
  - `"All existing tests continue to pass"`

- **Refactoring tasks:**
  - `"Behavior is unchanged: all tests that passed before this task still pass after"`
  - `"No new files are introduced unless explicitly justified"`
  - `"All existing tests continue to pass"`

- **CLI tasks:**
  - `"<command> --help output includes [specific flag or description]"`
  - `"<command> exits with code 1 on [invalid input condition]"`
  - `"Running <command> with valid input produces [specific file or output]"`
  - `"All existing tests continue to pass"`

---

## Apply Lessons Learned

After generating each task, check `specification/project/lessons-learned.md` (if read in Setup) for lessons relevant to that task's domain. Match by topic: bash scripting, YAML handling, git operations, TDD workflow, CLI dispatch, JSON output, shellcheck, etc.

If relevant lessons exist, add a `hints` field — a concise array of strings referencing the pattern, not the full lesson. Omit the `hints` field entirely if no lessons apply to the task.

Examples of concise hints:
- `"Use mapfile -t arr < <(cmd) not arr=($(cmd)) — avoids SC2207"`
- `"TDD suites must exit 0 regardless of results — document this in the file header"`
- `"Use read -r answer || answer='n' for EOF-safe interactive reads"`
- `"Use [ ! -s \"$file\" ] to test file-missing-or-empty in one check"`
- `"yq string scalars include surrounding quotes — strip with -r or sed"`

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
    hints:                          # optional — omit if no relevant lessons apply
      - "..."
    status: pending
    attempts: 0
```

After writing, tell the user:
> "`tasks/<feature-name>/tasks.yaml` has been written. Please review the file and make any adjustments needed. You have to commit the final tasks file before running `./scripts/implement-feature.sh <feature-name>` as this will be executed within a separate git worktree (in `<project-name>-feat-<feature-name>` sibling directory)."

## Priority order

If the feature you are working on contains tasks for writing test suites:
  - Prioritize them at the beginning of the feature implementation
  - Add explicit instructions in the description that the test suite is implemented first and expected to fail initially
  - A test implementation task is considered complete without a green test suite
  - DO NOT run the test suite after initial implementation without existing feature code
  - Ensure that the linter / shellcheck is running and does not throw errors for the test suite implementation
