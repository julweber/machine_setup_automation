---
name: feature-whatsup
description: Gathers current implementation status by checking tasks.yaml and agent logs, producing a concise summary of what's going on. Use when asking 'what is up?', 'current status', 'feature status'.
---

# Skill: feature-whatsup

You are a status reporter for ongoing feature implementations. Gather information from the tasks file and latest agent logs to produce a clear status report.

---

## Setup

### Detect main branch

IMPORTANT: always run `git branch --show-current` first

1. if we are on `main` or `master`
2. check the specification status via git: `git diff specification`
3. Create a short and concise summary of the current worktree changes
4. Tell the user to finish and commit the current specification changes, 
5. STOP and DO NOT perform the rest of the workflow described below for `main` or `master` branch

### Detect Feature Name

If we are not on `main` or `master`:

Determine the current feature name:
1. Strip the `feat/` prefix (e.g., `feat/cli-tool` → `cli-tool`)
2. If the branch does not start with `feat/`, inform the user: "Current branch does not appear to be a feature branch (`feat/<name>`). Please switch to the correct branch and try again."

### Read Tasks File

Read `tasks/<feature-name>/tasks.yaml` - this contains the task list, their status, and progress.

---

## Gather Status Information

1. **Find the latest agent log file:**
   - Check `tasks/agent_logs/` directory
   - Find the most recent `.jsonl` file (sorted by modification time or name which includes timestamp)
   - Read the last 50-100 lines of this file

2. **Extract key information from tasks.yaml:**
   - Total number of tasks
   - Number of passed tasks
   - Number of pending tasks  
   - The current/next pending task (first one with status: pending)
   - Any tasks marked as failed or skipped

3. **Extract recent progress from agent logs:**
   - Look for `SUB-TASK-COMPLETE` signals to identify recently completed tasks
   - Find any task completion summaries
   - Identify any errors or issues mentioned in the log
   - Note which task is currently being worked on (if visible)

---

## Produce Status Report

Generate a concise status report with the following sections:

```
# Feature: <feature-name>

## Overall Progress
- Passed: X/Y tasks
- Pending: Z tasks
- Current/Next Task: task-NNN - <title>

## Recent Activity (from latest log)
- Last completed task: task-NNN
- Key changes/implementation notes

## Test Status
- Total tests: X
- Passing: Y
- Failing: Z

## Implementation State
- Files created/modified recently
- Any blocking issues or errors

```

Keep the report concise and actionable. Focus on what the user needs to know to understand the current state and decide next steps.
