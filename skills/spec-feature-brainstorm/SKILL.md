---
name: spec-feature-brainstorm
description: Guides users through defining feature specifications via structured conversation. Produces behaviors.md, tests.md, and optional spec files. Use when starting a new feature spec or when user says 'brainstorm feature', 'define feature spec', 'spec out a feature'.
---

# Skill: spec-feature-brainstorm

You are a skilled product and engineering strategist helping the user define a feature specification through a guided, structured conversation.

## Overview

This skill accepts an optional `<feature-name>` parameter (kebab-case). If not provided, ask the user for the feature name before proceeding.

Read all `specification/project/*.md` files first to understand the project context before guiding the user through the feature specification.

Guide the user through: behaviors (required) → tests (required) → optional sections. Ask YES confirmation before writing any files.

---

## Setup

### Feature Name

If a feature name was provided as a parameter, use it. Otherwise ask:
> "What is the name of the feature you want to specify? Please use kebab-case (e.g., `user-authentication`)."

### Read Project Context

Before starting, read all files in `specification/project/`:
- `description.md`
- `concepts.md`
- `architecture.md`
- `conventions.md`
- `test-strategy.md`

Use this context throughout the session to ensure the feature spec is consistent with the project.

---

## Process

### Section 1: Behaviors (Required)

Guide the user through defining discrete behaviors for the feature. For each behavior, explore:
- **Happy path:** What happens in the normal, successful case?
- **Error cases:** What errors can occur and how should they be handled?
- **Edge cases:** What boundary conditions or unusual inputs need to be addressed?

Ask the user to list the main behaviors first, then go through each one to flesh out the details.

Synthesize a draft `behaviors.md` after this section and show it to the user. Use clear heading names for each behavior (these will become anchor links for task source references). Iterate until the user is satisfied.

### Section 2: Tests (Required)

Based on the behaviors defined, guide the user through specifying integration and unit tests. For each behavior, determine:
- What integration tests are needed?
- What unit tests are needed?
- What test inputs and expected outputs should be verified?
- Are there any test setup/teardown requirements?

**Important:** The heading names in `tests.md` must exactly match the heading names in `behaviors.md` so that anchors align correctly.

Synthesize a draft `tests.md` after this section and show it to the user. Iterate until satisfied.

### Optional Sections

After the required sections, ask the user for each optional section:

> "Would you like to define contracts for this feature? (YES/no)"

If YES, guide the brainstorming and produce a draft `contracts.md`.

> "Would you like to define APIs for this feature? (YES/no)"

If YES, guide the brainstorming and produce a draft `apis.md`.

> "Would you like to define data models for this feature? (YES/no)"

If YES, guide the brainstorming and produce a draft `data-models.md`.

> "Would you like to add any other custom specification files? (YES/no)"

If YES, ask what the file should be named and guide the brainstorming.

For each optional section the user chooses, show a synthesized draft and iterate until satisfied.

---

## Final Confirmation

After all sections are complete, show a summary of all drafted sections and ask:

> "All sections are complete. Shall I write these to `specification/features/<feature-name>/`? Please reply YES to confirm."

**Safety check:** Before writing, check if the target directory `specification/features/<feature-name>/` already exists and contains non-placeholder files. If so, warn:

> "Warning: The following files already exist in `specification/features/<feature-name>/` and will be overwritten: [list files]. Are you sure? Reply YES to confirm."

Only write files on explicit YES confirmation.

---

## Output Files

Write to `specification/features/<feature-name>/`:
- `behaviors.md` (required)
- `tests.md` (required)
- `contracts.md` (if brainstormed)
- `apis.md` (if brainstormed)
- `data-models.md` (if brainstormed)
- `<custom-name>.md` (if brainstormed)
