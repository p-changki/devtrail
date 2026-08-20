---
name: devtrail-worklog
description: Record work in the project's worklogs folder. One task = one folder.
triggers:
  - "write a worklog"
  - "update the worklog"
  - "/devtrail-worklog"
user_invocable: true
---

# Worklog

One task becomes one folder. The date and task name are in the folder name,
so skimming the list later shows you the arc.

## 🔑 Path

```bash
devtrail path projects       # project root
```

**Do not write outside the vault.** They used to pile up in `~/Desktop/worklogs/` — do not do that.
Split from everything in the vault, both halves were useless.
They go inside the project folder.

```
$(devtrail path projects)/<project>/worklogs/
└── YYYY-MM-DD_task-name/
    └── worklog.md
```

## Steps

### 1. Identify the project

Infer from the working directory name. Check it against the project list.

```bash
ls "$(devtrail path projects)"
```

If you are not sure, **ask once** and carry on.
If the project folder does not exist, do not create it — tell them to use
`⌘⇧P` in Obsidian, which creates the docs skeleton and hub too.

### 2. Task name

Infer from the branch name or the conversation. Short, kebab-case.

```
2026-08-20_login-token-fix
2026-08-20_report-flow-refactor
```

### 3. Write it

Fill this into `worklog.md`.

```markdown
---
tags:
  - type/doc
  - project/<project>
type: worklog
status: done
created: YYYY-MM-DD
updated: YYYY-MM-DD
project: <project>
---

# <task name>

## Background   ← required

What triggered this work:
1. Trigger — a request, a bug, or something you found
2. State before — what was wrong
3. The approach you chose and why — what the alternatives were

## What I did

- 

## Verification

- What you checked and how
- The result

## Left over

- [ ] 
```

> **Never leave "Background" empty.** Someone reading this in a few months
> needs *why it was done that way*, not *what was done*.

### 4. Appending

For "update the worklog", find the project's **most recent folder** and
append to it. Do not create a new one.

## Report

1. The path you created
2. A 3–5 line summary of the work
3. Next action, if any
