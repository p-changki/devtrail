---
name: devtrail-docs
description: File project documents in the right place, chosen by document type.
triggers:
  - "file this doc"
  - "save documentation"
  - "/devtrail-docs"
user_invocable: true
---

# Placing project documents

So you never have to think about where a document goes.

## 🔑 Paths

```bash
devtrail path projects
ls "$(devtrail path projects)"     # the project list
```

**Never hardcode the project list.** It differs per user.

## The docs skeleton

Projects created with `⌘⇧P` have this skeleton. The numbers are
**a reading order**.

```
docs/
├── 00-overview       what we are building and why
├── 01-product        requirements · PRD
├── 02-domain         domain model · vocabulary
├── 03-architecture   structure · technology choices
├── 04-data           schema · migrations
├── 05-infra          deploys · environments
├── 06-compliance     security · regulation
└── 07-delivery       release · operations
```

## Where things go

| Document type | Location |
|---|---|
| PRD · requirements | `01-product/` |
| Design · architecture | `03-architecture/` |
| Schema · data | `04-data/` |
| Deploy · infrastructure | `05-infra/` |
| Decision record (ADR) | `00-overview/` or the relevant area |
| Meeting notes | `00-overview/` |

**When it is ambiguous, ask.** Filed wrong means never found again.

## Steps

1. **Identify the project** — infer from the working directory; ask once if unclear
2. **Identify the document type** — read the content, pick from the table
3. **Filename** — `YYYY-MM-DD title.md`
4. **frontmatter**

```yaml
tags:
  - type/doc
  - doc/<type>
  - project/<project>
type: doc
doc_type: <type>
status: draft
project: <project>
```

## Do not

- Create folders outside the skeleton — eight is enough
- Overwrite an existing file — append `-2` if the name is taken
- Create the project folder yourself — point them at `⌘⇧P` in Obsidian,
  which creates the docs skeleton and hub too

## Report

```
✅ 2026-08-20 payment system design.md
   → Projects/myapp/docs/03-architecture/
```
