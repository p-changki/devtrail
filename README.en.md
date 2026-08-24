# DevTrail

[![CI](https://github.com/p-changki/devtrail/actions/workflows/ci.yml/badge.svg)](https://github.com/p-changki/devtrail/actions/workflows/ci.yml)

*[한국어](README.md) · [**English**](README.en.md)*

> A local second brain for developers: capture what you build, learn, and reference today—then use it again every week.

DevTrail is a **local Markdown workspace for capturing a large personal knowledge base and bringing it back into real work**. Its macOS CLI, menu bar app, and Obsidian Command Center connect GitHub activity, devlogs, project docs, web links, and YouTube learning in one workflow.

It is designed to help developers, job seekers, solo builders, and AI-assisted “vibe coders” get productive in Obsidian without first designing a complex system. Start from today’s devlog; later, find and reuse your own project context, documents, links, and learning notes. Your records stay as local files in your vault.

![DevTrail overview — Obsidian dashboard and menu bar app](docs/assets/devtrail-overview.png)

_See today’s record, projects, and library together in the Obsidian dashboard and menu bar app._

> **macOS beta:** [Download DevTrail 0.7.0 DMG](https://github.com/p-changki/devtrail/releases/tag/v0.7.0). Please share bugs and feedback through [Issues](https://github.com/p-changki/devtrail/issues).

## Who it is for

- Developers new to Obsidian or building a durable note-taking habit
- Solo developers who want GitHub work, devlogs, project docs, and references together
- macOS users who prefer a local Markdown-first workspace

It is not a general replacement for Raindrop, Readwise, or a web clipper. DevTrail focuses on bringing captured work and learning back into daily logs and weekly reviews.

## Install the beta and start in five minutes

### Easiest path — macOS app

1. Download `DevTrail-0.7.0.dmg` from the [release page](https://github.com/p-changki/devtrail/releases/tag/v0.7.0).
2. Open the DMG and drag **DevTrail** to **Applications**.
3. Control-click DevTrail in Applications and select **Open** once.
4. Choose your vault from the menu bar app and select **Review safe setup**.

This beta is not notarized by Apple yet. If macOS still refuses to open it, verify the release SHA-256 first, then run this once:

```bash
xattr -dr com.apple.quarantine /Applications/DevTrail.app
```

### Start with the CLI

```bash
curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash
devtrail init
```

Choose a vault and language, then safely add DevTrail to an existing vault or start fresh. The menu bar app gives you direct access to today’s log, GitHub activity, and link capture.

1. Choose a vault
2. Review the safe setup
3. Create today’s devlog
4. Save one link or quick note
5. Open the Obsidian dashboard

Existing notes are never moved or overwritten. You can preview changes before applying them, and reverse applied changes with `devtrail undo`.

## What you can do

| Need | DevTrail result |
|---|---|
| Today’s devlog | Creates a template, adds GitHub activity, optionally summarizes PRs with AI |
| Project docs | Syncs repository docs and shows project stages |
| YouTube link | Optionally summarizes and classifies available transcripts with your chosen AI |
| Web link | Saves title, description, and Open Graph metadata without AI and organizes it in the library |
| Weekly review | Generates a draft from this week’s records |

### Link library

Paste a URL into **Save link** in the menu bar, or run:

```bash
devtrail capture web --url https://example.com
devtrail capture web --url https://example.com --apply
devtrail capture web --organize --apply
```

Links are organized by a small `type`, area, topic, free tags, and domain. DevTrail classifies only when the evidence is clear—documentation, tools, design references, assets, data sources, or coding practice. Ambiguous links stay **uncategorized**. After a successful save, the input clears for the next URL.

## Safety promises

- Commands are dry-run by default; files change only with `--apply`.
- Existing notes, folders, and Obsidian settings are merged, never overwritten.
- Changes are journaled and can be inspected or reversed with `devtrail undo`.
- General web-link capture needs no AI, API key, or paid service.
- AI is optional and the menu bar shows running, success, and failure states.

## Components and requirements

- Requires **macOS**, Obsidian, `git`, and `jq`.
- GitHub activity requires `gh auth login`.
- Required Obsidian plugins: Shell commands, Templater, Dataview, and Auto Note Mover.
- `DevTrail Command Center` is an Obsidian plugin that reads paths created by the DevTrail CLI. It is prepared for Community Plugin distribution but is not registered yet; without the CLI it shows setup guidance instead of a broken view.

DevTrail is local-file first. Network access is limited to GitHub activity, plugin installation, and metadata requests for URLs you explicitly save.

## Check status and get help

```bash
devtrail doctor
devtrail app install
devtrail command-center install
devtrail undo
```

Please report bugs or ideas in [Issues](https://github.com/p-changki/devtrail/issues). Include `devtrail doctor` output and steps to reproduce when possible.

## Development

```bash
./scripts/verify-local.sh --fast
```

[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Architecture](docs/ARCHITECTURE.md) · [MIT License](LICENSE)
