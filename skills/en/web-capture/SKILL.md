---
name: devtrail-web-capture
description: Turn a web page into markdown and drop it in the Inbox. Promotion is a separate step.
triggers:
  - "save this page"
  - "capture this"
  - "/devtrail-web-capture"
user_invocable: true
---

# Web → Inbox

Where you put something you read so you can deal with it later.

## 🔑 Path

```bash
devtrail path inbox
```

## The Inbox is a holding area

**Do not try to finish it here.** Drop it, look again in 2 days, promote or
discard. Promotion is `/devtrail-promote`.

Once the Inbox passes 20, you are capturing faster than you are processing.
**At that point, tell them to empty it before capturing more.**

```bash
ls "$(devtrail path inbox)"/*.md 2>/dev/null | wc -l
```

## Steps

### 1. Fetch

If it is a URL, read it. If it is pasted text, use that.

### 2. Write it up

| Field | What goes there |
|---|---|
| Title | The original title. Derive one if there is none |
| Source / context | **Why you saved it** — without this, in 2 days you will not know |
| One-line capture | The single point |

**Do not transcribe the whole thing.** If there is a URL, a link is enough.
The point of capturing is not storage — it is **leaving yourself a reason to
come back**.

### 3. Save

Filename: `YYYY-MM-DD HHmm title.md`
Template: `$(devtrail path templates)/Inbox capture.md`

frontmatter must include:
```yaml
type: inbox-capture
status: inbox
source: <URL>
source_type: web
review_at: <2 days out>
```

An empty `review_at` means the hub's "due for review" never catches it.

## Do not

- Copy the full text — a link plus one line is enough
- Skip the Inbox and go straight to a zettel — it has to pass the gate
- Leave "why you saved it" blank

## Report

```
✅ 2026-08-20 1430 RAG chunking strategies.md → Inbox/
   ⚠️ Inbox is at 22 — clear it with /devtrail-promote
```
