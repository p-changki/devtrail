---
name: devtrail-youtube
description: Pull a YouTube video's captions, write it up, and file it in the vault. It rolls up into the devlog and hubs automatically.
triggers:
  - "summarize this video"
  - "youtube note"
  - "/devtrail-youtube"
user_invocable: true
---

# YouTube → vault

Analyze a YouTube video and file it. Handles several URLs at once.

## Requirements

- `yt-dlp` — `brew install yt-dlp`
- A DevTrail config — check with `devtrail doctor`

## 🔑 Always look paths up

**Never guess or hardcode a path.** Folder names differ per user.

```bash
devtrail path youtube        # absolute path to save the note
devtrail path --rel youtube  # relative path for Dataview FROM
devtrail path devlog         # devlog folder
```

If a path lookup fails, **stop** and point the user at `devtrail init`.
Creating files in the wrong place is not acceptable.

## Saving updates three places

| Where | What |
|---|---|
| `$(devtrail path youtube)/{date}-{slug}.md` | The note itself |
| `_index.md` in the same folder | The hub picks it up |
| "📺 Watched today" in today's devlog | Anything with `watched_at` = today |

⚠️ Those roll-ups read frontmatter. **Always fill in `type` · `watched_at` ·
`channel` · `tl_dr_oneline`.** Leave one empty and the note silently drops
out of the roll-up.

## Steps

### 1. Extract URLs

Must handle shorts, watch, and youtu.be.

```bash
echo "$INPUT" | grep -oE 'https?://(www\.)?(youtube\.com/(watch\?v=|shorts/)|youtu\.be/)[A-Za-z0-9_-]{11}'
```

> 🔴 Do not drop `youtube.com/shorts/`. Without it, shorts URLs are
> **skipped silently, with no error**.

### 2. Check for duplicates

If a note for that URL exists, skip it and say why.

```bash
grep -rl "$URL" "$(devtrail path youtube)" 2>/dev/null
```

### 3. Get the captions

```bash
yt-dlp --skip-download --write-auto-sub --sub-lang "en,ko" \
       --convert-subs srt -o "/tmp/dt-yt-%(id)s.%(ext)s" "$URL"
```

If there are no captions, record the failure and **move to the next URL.**
One failure does not stop the rest.

### 4. Analyze

Read the captions and fill these in. Do not add anything that is not in the
video.

- One-line summary (`tl_dr_oneline`)
- Five key points or fewer
- Timeline
- **What I will apply** (`key_for_me`) — this is why the note exists

### 5. Save

Use `$(devtrail path templates)/YouTube note.md`.
Filename is `YYYY-MM-DD-kebab-slug.md`.

### 6. Report

```
✅ [title] → path
❌ [URL] → reason (no captions / analysis failed)
```

## Do not

- Hardcode paths
- Leave frontmatter fields empty
- Add anything not in the captions
- Overwrite an existing note (skip duplicates)
