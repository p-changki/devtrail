---
name: devtrail-web-capture
description: Save a web URL as a categorized Markdown note in the developer library. No AI is used.
triggers:
  - "save this page"
  - "capture this"
  - "/devtrail-web-capture"
user_invocable: true
---

# Web → developer library

General web material leaves the existing Inbox alone and is saved beside it at
`Links/<area>/<purpose>`. For example, React docs go to
`Development/Frontend/Official Docs`; Lucide goes to `Design/Icons`.

## Saving rules

- No AI or external API is used.
- Read only title, description, and Open Graph metadata from the URL.
- Categorize only when domain, URL, or title gives a clear signal.
- When no domain rule matches, judge once more from words in the URL, title,
  and description, plus the TLD.
- Put still-uncertain material in `Common/Uncategorized`; do not guess. A wrong
  folder is worse than none — you can see "uncategorized", but a miscategorized
  link stays invisible until you go looking for it.
- Do not duplicate an existing URL or canonical URL.

## Run

```bash
devtrail path inbox --rel                         # inspect the current Library path
devtrail capture web --url "https://react.dev/"          # preview
devtrail capture web --url "https://react.dev/" --apply  # save
devtrail capture web --url "https://react.dev/" \
  --why "when revisiting hook rules" --project devtrail --apply  # save with context
devtrail capture web --organize                   # preview organizing old uncategorized links
```

Only `--apply` creates a note and missing `_index.md` hubs. Every change can be
reverted with `devtrail undo`.

Never guess or hard-code the folder path; query the current vault with
`devtrail path inbox --rel` first.

## Note metadata

```yaml
type: docs | tool | inspiration | asset | article | reference
area: frontend | backend | infra | data-ai | design | common
topic: <purpose>
why: "<why it was saved — only the person knows; may be empty>"
projects: [<project key>]
source: <domain>
url: <original URL>
```

**Never invent `why`.** Leave it empty unless the user said it. A guessed
reason makes the note untrustworthy later. Pass only keys that appear in
`devtrail project list` to `--project`.

`area` and `topic` power the folders, library `_index.md` hubs, and DevTrail
Library filters. Preserve the source link and metadata instead of copying an
entire page.

## Report

```
✅ React docs.md → Library/Links/Development/Frontend/Official Docs/
```
