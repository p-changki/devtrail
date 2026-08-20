---
name: devtrail-promote
description: Promote Inbox notes to zettels. Checks three conditions and promotes only what passes.
triggers:
  - "clear the inbox"
  - "promote notes"
  - "/devtrail-promote"
user_invocable: true
---

# Inbox → zettel

**Without this skill a Zettelkasten stalls.**
This friction is why the original vault sat at 7 inbox items and 12 zettels.

## 🔑 Paths

```bash
devtrail path inbox      # what gets promoted
devtrail path zettel     # where it goes
devtrail path moc        # topic hubs
```

## Three conditions — all of them

| # | Condition | Why |
|---|---|---|
| 1 | **Rewritten in your own words** | Copied text is not understanding |
| 2 | **A `#topic/` tag** | It gets gathered into a MOC later |
| 3 | **At least 2 links to related notes** | An unlinked note is never read again |

**Miss one and it does not get promoted.** Without the gate, zettels become
copies of the Inbox — and at that moment the system is a bin.

## Steps

### 1. Pick targets

```bash
ls -t "$(devtrail path inbox)"
```

Oldest first. Exclude `_index.md`.
If the user did not name a note, propose the **three oldest** and let them choose.

### 2. Judge

Read the note and decide which of three it is.

| Verdict | Condition | What to do |
|---|---|---|
| **Promote** | All three conditions can be met | Steps 3–5 |
| **Hold** | There is content but nothing to link to | Push `review_at` out 2 weeks |
| **Discard** | You will never look at it again | Delete after confirming |

**Always confirm before discarding.** Never delete someone's note on your own.

### 3. Write the promotion

- **Do not quote** the original — rewrite it in your own sentences
- Add `#topic/<slug>` — check for an existing topic first
- Find and link at least 2 related notes

```bash
# Check existing topics — inventing new ones fragments your MOCs
grep -rho '#topic/[^ ]*' "$(devtrail path zettel)" | sort | uniq -c | sort -rn
```

### 4. Save

Create `$(devtrail path zettel)/YYYYMMDDHHmm title.md`.
Follow the `Zettel.md` template.

frontmatter:
```yaml
type: zettel
status: seedling        # freshly promoted is always seedling
promoted_at: YYYY-MM-DD
source: <path to the original note>
review_at: <30 days out>
```

### 5. The original

**Do not delete** the Inbox note. Just mark it in frontmatter.

```yaml
status: promoted
promoted_to: <path to the new zettel>
```

### 6. MOC

If a MOC with the same `#topic/` exists, add a link to its list.
If there is none, suggest making one — do not make it yourself.

## Report

```
Promoted N · held N · discard suggested N

✅ <title> → zettel  (#topic/xxx · 2 links)
⏸ <title> → revisit in 2 weeks  (nothing to link to)
🗑 <title> → suggest discarding  (reason)
```

## Do not

- Promote without all three conditions
- Delete the original on your own
- Invent new `#topic/` values — check existing ones first
- Copy-paste the source text
