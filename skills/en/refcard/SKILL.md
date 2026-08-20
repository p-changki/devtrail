---
name: devtrail-refcard
description: Create reference cards for libraries and tools. The filename alone tells you what it was.
triggers:
  - "reference card"
  - "library note"
  - "/devtrail-refcard"
user_invocable: true
---

# Reference card

A note that kills **"wait, what was this again?"** after you use a library or tool.

## 🔑 Paths

```bash
devtrail path library    # libraries
devtrail path tool       # dev tools and sites
```

## The filename rule — this is the point

```
TanStack Query - server state management
SkeletonUI - loading states, gradients
npm trends - compare package download trends
```

**`name - one-line description`**.

The goal is that skimming the list tells you what each one was. Then you
never have to search.

## What to fill in

| Section | What goes there |
|---|---|
| One-line summary | Can be the same as the filename description |
| **When to use it** | The most important one — what situation should bring this to mind |
| Install | A command that actually works |
| Core usage | **The smallest working example** — do not copy the docs |
| Troubleshooting | Only what you hit yourself |
| Reference | Docs · GitHub |

## Rules

- **Do not transcribe the official docs.** A link is enough
- "When to use it" and "what I hit" are what make this note worth having
- Do not create one for something you have not used — wishlists go in Ideas

## Steps

1. Decide library or tool → pick the folder
2. Check whether one with that name already exists (update it if so)
3. Pull "when to use it" and any troubles out of the conversation
4. **Leave what you do not know blank.** Do not invent it

## Report

```
✅ TanStack Query - server state management → Libraries/
   Filled: when to use it · core usage
   ⚠️ Left troubleshooting blank (nothing hit yet)
```
