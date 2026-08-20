---
name: devtrail-pdca
description: Plan, design, analyze, report — and file the result as a project document.
triggers:
  - "make a plan"
  - "PDCA"
  - "/devtrail-pdca"
user_invocable: true
---

# PDCA — plan it, then record it

Run one of `plan` · `design` · `analyze` · `report` · `iterate`.
With no subcommand, it is `analyze`.

## 🔑 The difference: the result goes into the vault

The original printed to screen and stopped. **Then nothing is left by next
week.** Here the result is saved as a project document.

```bash
devtrail path projects
ls "$(devtrail path projects)"
```

| Subcommand | Saved to |
|---|---|
| `plan` | `<project>/docs/01-product/` |
| `design` | `<project>/docs/03-architecture/` |
| `analyze` | `<project>/docs/00-overview/` |
| `report` | `<project>/worklogs/<date>_<task>/` |
| `iterate` | Appends to the previous document |

If you cannot tell which project it is, **ask once**. If there is still no
answer, print to screen only. Do not stop the work over where to file it.

## What each one produces

### `plan`
- Problem — what is actually wrong
- Scope — what is in, what is out
- **Measurable success criteria** — a number or a condition, not "it works well"
- Acceptance checklist

### `design`
- Design overview
- Key decisions and why
- **Trade-offs** — what you gave up
- Risks and the rollback plan

### `analyze`
- Findings — **with evidence**. Say when something is a guess
- Assumptions
- Open questions
- **One** recommended next step

### `report`
- Done versus planned
- **How it was verified** — what you checked and how
- Gaps and root causes

### `iterate`
Read the previous result and write only what changed. Do not rewrite it all.

## Rules

- Never assert without evidence — if you do not know, it goes in "open questions"
- Success criteria must be **checkable**. "Faster" is not a criterion
- Report the path when you save a document

## frontmatter

```yaml
tags:
  - type/doc
  - doc/<plan|design|analyze|report>
  - project/<project>
type: doc
doc_type: <subcommand>
status: draft
```
