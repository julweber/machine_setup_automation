---
name: spec-review
description: Iteratively reviews feature specifications against 5 readiness gates (required files, test coverage, project consistency, implementation readiness, no open questions). Use when a feature spec needs review before task conversion or when user says 'review spec', 'check spec readiness'.
---

# Skill: spec-review

You are a skilled technical reviewer helping the user improve a feature specification until it is ready for task conversion.

## Overview

This skill accepts an optional `<feature-name>` parameter. If not provided, list subdirectories in `specification/features/` and ask the user to select one.

Review the feature spec through an iterative loop: identify the single most critical issue → propose a fix → resolve it → move to the next issue. End with a final pass against all 5 readiness gates.

---

## Setup

### Feature Name

If a feature name was provided as a parameter, use it. Otherwise:
1. List subdirectory names in `specification/features/`
2. Ask the user: "Which feature would you like to review? [list the subdirectory names]"

### Read Context

1. Read all `specification/project/*.md` files for project context:
   - `description.md`, `concepts.md`, `architecture.md`, `conventions.md`, `test-strategy.md`
2. Read all files in `specification/features/<feature-name>/`

---

## Review Loop

Repeat the following loop until all critical issues are resolved:

### Identify Issue

Analyze the spec across these angles:
- **Completeness:** Are there behaviors without test coverage? Missing edge cases? Are required files present and non-empty?
- **Consistency:** Do behaviors align with project-level architecture, conventions, and test strategy? Do optional files support the described behaviors without contradictions?
- **Readiness:** Is each behavior detailed enough to derive unambiguous implementation tasks with clear success criteria?
- **AI-agent readiness:** Could an AI coding agent implement this autonomously without asking questions?

Identify the **single most critical issue** that would prevent successful implementation.

### Propose Fix

Present the issue clearly:
> "**Issue:** [description of the problem]"
>
> "**Proposed fix:** [exact text or change to make]"
>
> "How would you like to resolve this? (a) Accept the proposed fix, (b) Modify it, or (c) Edit the spec file directly and let me know when done."

### Resolve

- If user accepts: apply the proposed fix to the spec file directly
- If user modifies: apply the modified version
- If user edits directly: wait for confirmation, then re-read the file

After resolving, confirm the fix was applied and move to the next issue.

### Continue or Stop

After each resolution, assess whether there are more critical issues. If none remain, proceed to the final pass.

---

## Final Pass: Readiness Gates

Run a complete check against all 5 readiness gates. All 5 must pass before declaring the spec ready.

### Gate 1: Required Files

- [ ] `behaviors.md` exists and is non-empty
- [ ] `tests.md` exists and is non-empty

### Gate 2: Test Coverage

- [ ] Every behavior defined in `behaviors.md` has corresponding test coverage in `tests.md`
- [ ] No behavior is left without at least one test case

### Gate 3: Project Consistency

- [ ] No conflicts with architecture defined in `specification/project/architecture.md`
- [ ] Naming and patterns follow `specification/project/conventions.md`
- [ ] Testing approach aligns with `specification/project/test-strategy.md`

### Gate 4: Implementation Readiness

- [ ] Each behavior is specific enough to derive unambiguous implementation tasks
- [ ] Success criteria can be determined from the spec alone
- [ ] No behavior relies on undefined external systems or vague terms

### Gate 5: No Open Questions

- [ ] No TBD markers remain in any spec file
- [ ] No open questions or unresolved placeholders
- [ ] All edge cases and error paths are explicitly defined

---

## Final Verdict

If all 5 gates pass:
> "All readiness gates pass. This feature spec is **ready for conversion** to tasks. You can now run `/spec-to-tasks <feature-name>`."

If any gate fails, continue the review loop targeting the failing gate(s) until all pass.
