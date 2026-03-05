---
name: feature-results-to-spec
description: Reads progress.txt from a completed feature run and extracts lessons learned into specification/project/lessons-learned.md. Deduplicates and merges with existing lessons, organises by derived categories, and shows a git diff at the end. Use after a feature implementation run or when user says 'feature review', 'feature result to spec'.
---

# Skill: feature-results-to-spec

You are a technical analyst capturing lessons learned from a completed feature implementation run into the project specification.

## Overview

Read `progress.txt` for the current feature, extract insights, and write them into `specification/project/lessons-learned.md` — organised by category, deduplicated against existing content. Show a git diff at the end.

---

## Setup

### Detect Feature Name

Determine the current feature name from the active git branch:
- Run `git branch --show-current`
- Strip the `feat/` prefix (e.g., `feat/user-authentication` → `user-authentication`)
- If the branch does not start with `feat/`, inform the user: "Current branch does not appear to be a feature branch (`feat/<name>`). Please switch to the correct branch and try again."

### Read Inputs

1. Read all `specification/project/*.md` files first — to build project context and focus:
   - `description.md`, `concepts.md`, `architecture.md`, `conventions.md`, `test-strategy.md`
   - Use this context throughout to judge relevance, categorise accurately, and detect spillover into existing spec files.
2. Read `specification/project/lessons-learned.md` if it exists — to enable deduplication and merging.
3. Read `tasks/<feature-name>/progress.txt` — this is the primary source of lessons learned.

---

## Extract Lessons

Analyse `progress.txt` and extract:

- **Patterns discovered** — reusable approaches, successful techniques
- **Gotchas and pitfalls** — things that went wrong, caused retries, or required workarounds
- **Implementation insights** — non-obvious decisions made during implementation
- **Test findings** — anything learned about the test strategy in practice
- **Any other notable learnings** — failure reports, blocked tasks, recurring issues

For each extracted lesson, note:
- The lesson itself (concise, generalised — not feature-specific)
- The feature it came from (for attribution, noted inline)
- A candidate category (derived from the content — do not use a fixed list)

---

## Categorise and Deduplicate

### Derive Categories

Group the extracted lessons into categories based on their content. Derive category names from the lessons themselves (e.g., "Database Patterns", "Error Handling", "Test Setup", "API Design", "Dependency Management"). Do not use a fixed predefined category list.

### Deduplicate

Compare each extracted lesson against existing entries in `specification/project/lessons-learned.md`:
- If a lesson is substantially the same as an existing one, skip it
- If a lesson extends or refines an existing one, merge them into a single improved entry
- Only add genuinely new lessons

---

## Check for General Concept Spillover

After categorising, assess whether any lesson is general enough to belong in an existing project spec file:
- A lesson about naming or code style → could belong in `specification/project/conventions.md`
- A lesson about system structure or tech choices → could belong in `specification/project/architecture.md`
- A lesson about testing approach → could belong in `specification/project/test-strategy.md`

If any such lessons are identified, ask the user:

> "I found [N] lesson(s) that may also be relevant for existing project spec files:
>
> - [Lesson A] → could be added to `conventions.md`
> - [Lesson B] → could be added to `architecture.md`
>
> How would you like to handle these? (a) Add to `lessons-learned.md` only, (b) Add to the relevant project spec file only, (c) Add to both, (d) Skip"

Apply the user's choice before writing.

---

## Write `lessons-learned.md`

Write `specification/project/lessons-learned.md` directly (no confirmation needed). Structure the file as follows:

```markdown
# Lessons Learned

## <Category Name>

- **[Lesson title]** — [Concise description of the lesson]. *(from: <feature-name>)*

## <Another Category>

- ...
```

Rules:
- Top-level sections are categories, sorted alphabetically
- Each lesson is a bullet under its category
- Each lesson includes inline feature attribution: `*(from: <feature-name>)*`
- Merged/refined lessons retain attribution from all contributing features
- Keep lessons concise and generalised — avoid feature-specific implementation details

---

## Show Git Diff

After writing the file, run:

```bash
git diff specification/project/lessons-learned.md
```

Display the full output to the user so they can review exactly what was added or changed.
