# DevTrail

[![CI](https://github.com/p-changki/devtrail/actions/workflows/ci.yml/badge.svg)](https://github.com/p-changki/devtrail/actions/workflows/ci.yml)

*[한국어](README.md) · **English***

> A CLI that sets up **a complete Obsidian vault for engineering notes** —
> folder structure, note templates, auto-filing, GitHub activity, AI skills.

Notes accumulate without you writing them by hand, and what accumulates
rolls up into weekly reviews.

> **Platform**: macOS. Linux is not tested yet.
>
> **A note on the English support**: DevTrail was built in Korean first and
> English support landed in v0.3. Everything you see is English — folder
> names, note templates, in-vault guides, every CLI message, and the AI
> skills. `devtrail init` asks which language before anything else.
>
> Development still happens in Korean (comments, commit messages, internal
> docs). That does not reach you, but it is worth knowing before you open
> a PR.

---

## 30 seconds

```bash
curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash

devtrail init        # interactive setup
                     #   1) language — English / 한국어
                     #   2) vault path
                     #   3) how to install — add to this vault / start fresh / isolated
                     #   4) root folder name · modules · GitHub · AI
                     # → open the vault in Obsidian, install 4 plugins, restart
devtrail obsidian    # merge plugin config, templates, hotkeys
devtrail doctor      # tells you exactly what is not working
```

Already have a vault? That works too. `init` scans it first and offers to
**use your existing folders** rather than making new ones.

---

## What you get

Under the root you choose (say `MyVault/`):

```
MyVault/
├── Dashboard.md           today and this week at a glance
├── Daily check-in.md
├── Dev/
│   ├── Devlog/            by date. GitHub activity lands here automatically
│   ├── Notes/
│   │   ├── Frontend/  Backend/  DevOps/  Infra/  Testing/  General/
│   ├── Troubleshooting/  Ideas/  YouTube/  Libraries/  Tools/  AI/  Todo/
│   ├── Weekly/  Monthly/  Retro/     Retro splits into Weekly·Monthly·Quarterly·Project
│   ├── Projects/          per-repo docs skeleton
│   ├── RepoDocs/          `devtrail sync` pulls project docs in
│   └── Study/
├── Library/
│   ├── 00_Inbox/          dump things here first
│   ├── 10_Sources/        attachments · originals
│   ├── 20_Zettel/         only what you promoted. MOC included
│   └── 30_Archive/
├── Templates/             22 note templates
└── Guides/                getting started · folders and tags · hotkeys · extending
```

**Every folder gets an `_index.md` hub** that shows only that folder's notes.

New notes **file themselves** based on tags.
Tag a note `#type/dev-note/frontend` and it moves to `Dev/Notes/Frontend/`.

### Tags never change with language

This matters more than it sounds. Folder names are translated; **keys and tags
are not.** `#type/dev-note/frontend` is the same in both languages, so auto-filing,
hub queries, and AI skills keep working regardless of the language you pick.

### Modules — take what you need

| Module | What | Default |
|---|---|---|
| `devlog` | Devlog + GitHub activity | **required** |
| `review` | Weekly · monthly reviews | on |
| `project` | Project structure + docs skeleton | on |
| `pkm` | Library · zettel · MOC | on |
| `learn` | Learning system | on |
| `personal` | Personal (journal · books · scraps) | off |

Add later: `devtrail augment personal --apply`

---

## If you already have a vault

Probably your biggest worry. **Nothing moves.**

`devtrail scan` diagnoses first — it never writes.

```
Vault
  notes  1727 · folders 84
  meta   frontmatter 41%

Folder roles (inferred)
  devlog    confidence 0.92   312 notes   Daily

Suggestion
✅ Add to your existing vault — 1727 notes found
   Uses your folders as-is and only maps settings. Notes are not moved.
```

Roles are inferred from **what the folders contain**, not their names.
You make the final call.

Map `Daily/` as your devlog and DevTrail uses that folder — it will not create
`Dev/Devlog` alongside it.

### Three install modes

| | When | Auto-move | Your settings |
|---|---|---|---|
| **New** | empty vault | on | — |
| **Existing** | vault already in use | **Manual** | formatting rules untouched |
| **Isolated** | safest | inside our tree only | untouched |

**Isolated** installs into a new subtree only. Don't like it? Delete the folder.

---

## Safety contract

This tool writes into your vault, so this comes before features.

**1. It merges. It does not overwrite.**
Every Obsidian config write is backed up first. If the backup fails, DevTrail
**stops without touching the original.** Your hotkeys, auto-move rules, and
tags are preserved.

**2. Dry-run is the default.**
Anything that changes your vault shows you what it would do first.
You need `--apply` for it to write.

**3. It is reversible.**

```bash
devtrail undo                    # change history
devtrail undo <ID>               # preview — changes nothing
devtrail undo <ID> --apply
```

Folders are removed **only when empty**. If you put notes in one, it stays —
and DevTrail tells you it stayed.

**4. Re-running is safe.**
`augment` creates **only what is missing**. Notes you edited stay as they are.

---

## Commands

### Setup · diagnose

```bash
devtrail init              interactive setup
devtrail scan [path]       diagnose a vault — structure · meta · conflicts (read-only)
devtrail doctor            dependencies · auth · permissions · automation
devtrail obsidian          merge Obsidian settings
devtrail augment [module]  create only missing folders and hubs
devtrail project <sub>     register projects (add|list)
devtrail template <sub>    note templates (list|diff|update)
devtrail skills <sub>      AI skills (install|sync|list|remove)
```

### Record

```bash
devtrail activity [date]   insert GitHub issues/PRs into the devlog
devtrail summary  [date]   AI-summarize merged PRs in plain language
devtrail weekly            draft this week's review
devtrail backfill [date]   fill in past dates
devtrail sync              project docs → vault
```

### Projects

```bash
devtrail project add my-app                    # register + docs skeleton
devtrail project add acme-fe --section acme    # group repos into one section
devtrail project list                          # see what is registered
```

A project made with `⌘⇧P` still needs registering here before it shows up in
the devlog and dev-note pickers. Templater cannot call the shell, so this
cannot be automated.

### Manage

```bash
devtrail update            update DevTrail itself
devtrail undo [ID]         revert
devtrail config [get|set]  settings  (config set lang en)
devtrail path [key]        resolve a vault path
devtrail app <sub>         menu bar app (install|start|stop|status|uninstall)
devtrail dashboard         web dashboard
devtrail install-schedule  register automatic runs
devtrail uninstall         remove automation (never touches your vault)
```

---

## AI skills

Twelve skills for AI tools like Claude Code. Install with
`devtrail skills install`. Each one calls `devtrail path` at runtime, so it finds
**your actual folder names** — whatever language and whatever you renamed them to.

| | |
|---|---|
| `youtube` | pull captions, summarize, file into the vault |
| `web-capture` | web page → markdown in Inbox |
| `promote` | Inbox → zettel (3-item checklist) |
| `moc` | group scattered notes by topic |
| `rollup` | devlog → weekly → monthly |
| `worklog` | one task = one folder |
| `docs` | put project docs in the right place |
| `pdca` | plan · design · analyze · report |
| `qa-check` | reproducible QA checklists |
| `refcard` | library reference cards |
| `study-log` | learning progress |
| `vault-health` | Inbox backlog · orphans · broken links |

**DevTrail does not require an AI tool.** Skills are optional.

> Skills resolve paths through `devtrail path` at run time, so they follow
> whatever you named your folders — and whichever language you chose.

---

## Requirements

| | |
|---|---|
| **Required** | macOS · `bash` · `git` · `jq` · `python3` |
| **4 Obsidian plugins** | Shell commands · Templater · Dataview · Auto Note Mover |
| **Recommended** | Calendar · Omnisearch · Linter · Homepage |
| **GitHub activity** | `gh` (`brew install gh && gh auth login`) |
| **AI summaries** | Claude or OpenAI (optional) |

DevTrail **does not reimplement plugins.** It guides you to install them, then
merges configuration once they are active. `devtrail doctor` tells you what is
missing.

---

## Check `doctor` first

You never have to guess when something breaks.

```
$ devtrail doctor

Dependencies
✅ jq   ✅ gh   ✅ git   ✅ rsync

Obsidian
❌ required plugin missing: dataview
⚠️  alwaysUpdateLinks is off — moving notes will break links
```

It reports what is wrong **and how to fix it**.

---

## Where things live

| | |
|---|---|
| Installation | `~/.devtrail/src/` |
| Config | `~/.devtrail/devtrail.config.json` |
| Change journal | `~/.devtrail/journal/` |
| Vault | wherever you chose |

`devtrail uninstall` removes automation (launchd) only. **It never touches your notes.**
The menu bar app is removed separately with `devtrail app uninstall`.

---

## Current state

**Works** — vault structure · adding to an existing vault · 3 install modes ·
22 note templates · per-folder hubs · auto-filing · GitHub activity and PR
summaries · weekly reviews · 12 AI skills · undo · menu bar app · web dashboard

**English coverage** — complete. Folder names, folder hubs, the dashboard and
daily check-in, all 22 note templates, the in-vault guides, every CLI message,
and all 12 AI skills. Tags and frontmatter keys are identical in both
languages, so auto-filing and Dataview queries do not care which you picked.

**Not yet** — Linux · Windows · git hosts other than GitHub · note apps
other than Obsidian

**In testing** — long-term use on real vaults. Hit a bug? Open an
[issue](https://github.com/p-changki/devtrail/issues). Including
`devtrail doctor` and `devtrail scan` output makes it much faster to fix.
Issues in English are welcome.

---

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Design tokens](docs/design-tokens.md) · [Changelog](CHANGELOG.md)

```bash
./tests/run.sh        # run this before committing
```

> Development happens in Korean — comments, commit bodies, and internal docs.
> English pull requests and issues are welcome; replies may be in Korean.

⚠️ macOS ships bash **3.2**. `"$n개"` dies there — write `"${n}개"`.

---

## License

[MIT](LICENSE)
