---
name: devtrail-moc
description: Create and update topic MOCs. Pull scattered notes together by subject.
triggers:
  - "make a MOC"
  - "organize by topic"
  - "/devtrail-moc"
user_invocable: true
---

# Topic MOC

Once zettels pile up you need an entrance per topic. A MOC (Map of Content)
is that entrance.

## 🔑 Paths

```bash
devtrail path moc        devtrail path zettel
```

## Check existing topics first

```bash
grep -rho '#topic/[^ ]*' "$(devtrail path zettel)" | sort | uniq -c | sort -rn
```

**Inventing new topics freely fragments your MOCs.**
If `#topic/react` and `#topic/reactjs` both exist, each one is half a map.

## When to make one

| Situation | Call |
|---|---|
| 3+ notes with the same `#topic/` | Time to make one |
| 1–2 notes | Too early — just keep the tag |
| A MOC already exists | Update it, do not make another |

## Steps

### Creating one

1. Pick the topic slug (make sure it does not collide)
2. Create `$(devtrail path moc)/<topic> MOC.md`
3. Follow the `MOC.md` template
4. Fill in the **learning path** — what to read at basic/intermediate/advanced

### Updating one

1. Leave the Dataview block alone — it needs no maintenance
2. Curate **key notes by maturity** by hand
   - Evergreen (understood) / Budding (in progress) / Seedling (just collected)
3. Update the **open questions** — what you still do not know is where this
   MOC goes next
4. Link related MOCs

## Orphan notes

Find zettels with no `#topic/` and suggest which MOC they belong to.
**Suggest only. Do not assign tags on your own.**

## Report

```
Updated: RAG MOC
  Evergreen 2 · Budding 5 · Seedling 3
  Added 2 open questions
  ⚠️ 4 zettels with no #topic/ — suggestions below
```
