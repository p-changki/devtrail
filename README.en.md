# DevTrail

[![CI](https://github.com/p-changki/devtrail/actions/workflows/ci.yml/badge.svg)](https://github.com/p-changki/devtrail/actions/workflows/ci.yml)

*[한국어](README.md) · [**English**](README.en.md)*

> Turn your Obsidian vault into a calm daily workspace for developers.

DevTrail combines a macOS CLI, menu bar app, and Obsidian Command Center to connect GitHub activity, devlogs, project docs, and learning material in one local Markdown workflow.

## Who it is for

- Developers new to Obsidian or building a durable note-taking habit
- Solo developers who want GitHub work, devlogs, project docs, and references together
- macOS users who prefer a local Markdown-first workspace

It is not a general replacement for Raindrop, Readwise, or a web clipper. DevTrail focuses on bringing captured work and learning back into daily logs and weekly reviews.

## Start in five minutes

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
