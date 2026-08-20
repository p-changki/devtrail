---
name: devtrail-vault-health
description: Check vault hygiene — Inbox backlog, orphans, broken links, missing metadata.
triggers:
  - "vault health"
  - "check my vault"
  - "/devtrail-vault-health"
user_invocable: true
---

# Vault health check

## 🔑 Run this first

```bash
devtrail scan --json
```

It gives you folders, tags, frontmatter coverage, and conflicts.
**Use that output instead of counting things yourself.**

## What to check

### 1. Inbox backlog

```bash
find "$(devtrail path inbox)" -name '*.md' -mtime +14 -not -name '_index.md'
```

If anything is older than 14 days, suggest `/devtrail-promote`.
Past 20 items, **warn** — beyond that nobody keeps up.

### 2. Orphan notes

Notes with no links in and none out. They never get read again.

Dataview counts these accurately. The hub's "no links" block already does it.

### 3. Broken links

```bash
grep -rho '\[\[[^]|]*' "$(devtrail path --rel . 2>/dev/null || echo .)" 2>/dev/null
```

Check whether each `[[...]]` target actually exists.
**Do not fix them automatically** — you cannot tell a typo from a deliberate
forward link.

### 4. Missing metadata

Look at `fields` in `devtrail scan`.
**Count "key present but empty" separately** — merging the two overstates
coverage.

When coverage is low, say that hub queries are running on approximations.

### 5. Gaps in the devlog

How many days are missing. **Do not nag about doing it daily.**
The point is to show the streak broke and make restarting easy.

## Report

Worst first.

```
🔴 Inbox at 23 (20 recommended) · 8 older than 14 days
🟡 12 orphan notes
🟡 type coverage 21% — hubs are approximating
🟢 0 broken links
🟢 No gaps in the last 7 days

Next: clear the Inbox with /devtrail-promote
```

## Do not

- Fix anything automatically — report only
- Give it a score — pressure by number makes people stop opening the vault
- Suggest deleting notes (an orphan may get linked later)
