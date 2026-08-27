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

### 2.5 Determine the learning goal and video genre

If the input includes `Goal:` or `What I want to learn:`, use it as the learning goal.
Otherwise infer a one-sentence goal from the title and captions, and label it in the
note as `Inferred learning goal`. Do not reduce the goal to a generic "video summary";
state what the user can later decide, do, or verify with this note.

Choose one genre below. Use `general` when it is ambiguous.

- `design-critique` — design reviews and portfolio feedback
- `tutorial` — technical, implementation, or tool lessons
- `tool-review` — tool, service, or product reviews/comparisons
- `career-interview` — career advice, interviews, or experience reports
- `news-trend` — news, industry trends, or market commentary
- `strategy` — business, product, or marketing strategy
- `general` — other informational videos

### 3. Get the captions

```bash
yt-dlp --skip-download --write-sub --write-auto-sub --sub-langs "en.*,ko.*" \
       --convert-subs srt -o "/tmp/dt-yt-%(id)s.%(ext)s" "$URL"
```

Try both creator-provided and auto-generated captions. Inspect the command output and
the generated `.srt` files, record the outcome as below, and **move to the next URL.**
One failure does not stop the rest.

| Condition | Record as |
|---|---|
| `Video unavailable`, `Private video`, or sign-in/age/region restriction errors | Video inaccessible |
| The command succeeds but no `.srt` file is generated | No captions |
| Any other yt-dlp error | Caption extraction failed — summarized error |

If the video plays in a browser but is inaccessible here, the account permission or
browser session may differ. Only then, a user-provided, one-time Netscape `cookies.txt`
path may be used as follows. Never save or print the cookie file path or its contents in
notes, configuration, or logs.

```bash
yt-dlp --cookies "$YTDLP_COOKIES_FILE" --skip-download --write-sub --write-auto-sub \
       --sub-langs "en.*,ko.*" --convert-subs srt \
       -o "/tmp/dt-yt-%(id)s.%(ext)s" "$URL"
```

If the cookie retry still reports inaccessible, report that status; do not promise a
bypass.

### 4. Analyze

Read the captions and extract **information for decisions first**. This is not merely a
plot summary. Do not add anything that is not in the video.

#### Common output for every genre

Place `## Reusable decision criteria` immediately after the TL;DR at the top of the
note. Write 3–7 concise decision cards, each containing:

- **Judgment/claim** — a reusable criterion the speaker endorses or rejects
- **Context** — when the judgment applies
- **Reason or signal** — the speaker's rationale or an observable warning sign
- **My application** — one action or check for the user's next project
- **Classification** — `principle` / `conditional advice` / `personal preference` / `factual claim`
- **Evidence** — a short quote and timestamp when available; explicitly state when no timestamp exists

Do not turn a screen-specific instruction such as `64 → 48` into a universal rule.
Separate the principle (for example, reducing type when it dominates visual hierarchy)
from the local prescription. Keep the speaker's opinion, caption-supported facts, and
AI inference separate; label AI inference as `Interpretation`.

#### Genre-specific output

Add only the section for the selected genre.

| Genre | Also extract |
|---|---|
| `design-critique` | Problem signals · revision direction · exceptions/brand context · reusable checklist |
| `tutorial` | Prerequisites · steps · failure points · adoption order |
| `tool-review` | Suitable users · strengths/constraints · alternatives · adoption decision |
| `career-interview` | Speaker experience · generalizable advice · case-specific advice |
| `news-trend` | Verified facts · speaker interpretation · affected groups · required response |
| `strategy` | Claim · customer/market premise · success conditions · risks · experiment to validate |

Keep only items directly tied to the learning goal in `## Insights & applications`.
Put detailed summaries, sequence/timeline, and full captions after it as supporting
material for later verification.

- One-line summary (`tl_dr_oneline`)
- Learning goal and genre
- 3–7 reusable decision criteria
- **What I will apply** (`key_for_me`) — this is why the note exists
- **Area and topic** (`category` · `area` · `topic`) — how the library is found later

Use one matching `category` and `area`: `frontend`, `backend`, `infra`,
`data-ai`, `design`, or `common`. Choose one evidence-based `topic` such as
`ui-components`, `api`, `database`, `deploy-operations`, `models-tools`,
`icons`, or `landing-references`; do not leave it `uncategorized` when the
captions provide enough context.

### 5. Save

Use `$(devtrail path templates)/YouTube note.md`.
Filename is `YYYY-MM-DD-kebab-slug.md`.

### 6. Report

```
✅ [title] → path
❌ [URL] → reason (video inaccessible / no captions / caption extraction failed / analysis failed)
```

## Do not

- Hardcode paths
- Leave frontmatter fields empty
- Add anything not in the captions
- Overwrite an existing note (skip duplicates)
