<%*
// ── DevTrail shared helpers v2 ────────────────────────────────────────────
// Prepended to every template. This is what keeps vault paths out of them.
//
// It finds the path-map note *by filename*, so it works wherever that note
// lives — and no template contains a single character of a vault path.
const DT = await (async () => {
  const f = app.vault.getFiles().find(x => x.name === "_devtrail-paths.md");
  if (!f) return { paths: {}, root: "", ok: false };
  try {
    const raw = await app.vault.read(f);
    const m = raw.match(/```json\s*([\s\S]*?)```/);
    if (!m) return { paths: {}, root: "", ok: false };
    return Object.assign(JSON.parse(m[1]), { ok: true });
  } catch (e) {
    return { paths: {}, root: "", ok: false };
  }
})();

// Look up a path. Falls back so the template never dies.
const dtPath = (key, fallback) => (DT.paths && DT.paths[key]) || fallback || "";

// Strip characters that are not valid in filenames.
const dtSafe = (s) => (s || "").replace(/[\\/:*?"<>|#\[\]]/g, "-").replace(/\s+/g, " ").trim();

// Append -1, -2 if the name is taken. Never overwrite.
const dtUnique = (folder, base) => {
  let name = base, i = 1;
  while (app.vault.getAbstractFileByPath(`${folder}/${name}.md`)) name = `${base}-${i++}`;
  return name;
};

// Clean up the empty orphan note when the user cancels.
const dtCancel = (file) => {
  tp.hooks.on_all_templates_executed(async () => {
    if (file) await app.vault.trash(file, true);
  });
};

// Read the project list from config; prompt if there is none.
// (The original hardcoded a PROJECTS array — every new project meant editing
//  the template.)
const dtProjects = () => (DT.projects && DT.projects.length ? DT.projects : []);

// Devlog filename. Follows naming.devlog_file from config.
// ⚠️ Hardcoding this creates a different file than `devtrail activity` does.
const dtDevlogName = (date) => {
  const pat = (DT.naming && DT.naming.devlog_file) || "{{DATE}} devlog.md";
  return pat.replace("{{DATE}}", date).replace(/\.md$/, "");
};

// Templates folder name, for query exclusions.
const dtTplFolder = () => ((DT.paths && DT.paths.templates) || "Templates").split("/").pop();

// Tag namespaces. Only the two a user types by hand vary by language.
const dtNs = (k) => (DT.ns && DT.ns[k]) || k;

// Weekly review filename. Follows naming.weekly_file from config.
const dtWeeklyName = (iso) => {
  const pat = (DT.naming && DT.naming.weekly_file) || "{{ISOWEEK}} weekly.md";
  return pat.replace("{{ISOWEEK}}", iso).replace(/\.md$/, "");
};

// Project key -> PR summary section.
//
// ⚠️ The key and the section can differ — that is how fe/be repos group into
//    one section. The devlog's #### heading uses the *section*; tags and links
//    use the *key*.  ADR 0001 D5a.
// Old path maps have no project_sections — then the key is used as-is.
const dtSection = (key) => (DT.project_sections && DT.project_sections[key]) || key;

// Keys -> sections (deduplicated, input order preserved)
const dtSections = (keys) => [...new Set((keys || []).map(dtSection))];

// The keys that belong to a section
const dtKeysOf = (keys, section) => (keys || []).filter(k => dtSection(k) === section);
_%>
<%*
// If today's devlog already exists, open it instead of creating another.
const devlogDir = dtPath("devlog");
const name = dtDevlogName(tp.date.now("YYYY-MM-DD"));
const target = `${devlogDir}/${name}.md`;
const existing = app.vault.getAbstractFileByPath(target);
if (existing) {
  const temp = app.workspace.getActiveFile();
  tp.hooks.on_all_templates_executed(async () => {
    await app.workspace.getLeaf(false).openFile(existing);
    if (temp && temp.path !== target) await app.vault.trash(temp, true);
  });
  return;
}
await tp.file.move(`/${devlogDir}/${name}`);

// Pick today's projects to create the #### subheadings.
// Those subheadings are where `devtrail summary` inserts PR summaries —
// with no section, the summary is skipped without an error.
const PROJECTS = dtProjects();
const DONE = "✅ Done choosing";
const OTHER = "✏️ Type it in";
const picked = [];
while (true) {
  const menu = [DONE, ...PROJECTS.filter(p => !picked.includes(p)), OTHER];
  const ph = picked.length
    ? `Picked: ${picked.join(", ")} — add more or choose Done`
    : "📝 Projects you are working on today (none? choose Done)";
  const choice = await tp.system.suggester(menu, menu, false, ph);
  if (!choice || choice === DONE) break;
  if (choice === OTHER) {
    const c = await tp.system.prompt("Project name");
    if (c && c.trim()) picked.push(c.trim());
  } else picked.push(choice);
}
// The heading is the *section*; the links are the *keys*. Several repos
// sharing one section produce a single heading.
// ⚠️ picked holds canonical keys only, and frontmatter keeps them as keys —
//    that is what ties #project/<key> to the project folder.  ADR 0001 D5a.
const projectBlock = picked.length
  ? dtSections(picked).map(sec => `#### ${sec}\n- \n`).join("")
  : "#### \n- \n";

// frontmatter and tags. Both use *keys*.
//
// ⚠️ No singular project: here. You work on several projects in a day, so the
//    devlog as a whole cannot belong to one. A dev note is one note about one
//    project, so it keeps the singular form.  ADR 0001 D5.
const projectList = picked.length ? `[${picked.join(", ")}]` : "[]";
const projectTags = picked.map(k => `  - project/${k}\n`).join("");

const P = {
  devlog:  devlogDir,
  youtube: dtPath("youtube"),
  root:    DT.root || "",
  tpl:     dtTplFolder(),
};
-%>
---
tags:
  - type/devlog
<% projectTags %>type: devlog
projects: <% projectList %>
date: <% tp.date.now("YYYY-MM-DD") %>
day_of_week: <% tp.date.now("dddd") %>
created: <% tp.date.now("YYYY-MM-DD") %>
updated: <% tp.date.now("YYYY-MM-DD") %>
---

# 📅 <% tp.date.now("YYYY-MM-DD (ddd)") %> devlog

## ☀️ Morning — top 3 for today

- [ ] 
- [ ] 
- [ ] 

## Work log

<!-- Merged-PR summaries go inside the '#### <repo>' sections below.
     ⚠️ With no section, the summary is skipped without an error. -->

### Morning

<% projectBlock %>
### Afternoon

- 

## Issues / PRs

<!-- DevTrail inserts GitHub/Linear activity directly under this heading.
     If you rename it, change headings.issues_pr in devtrail.config.json too. -->

## 📺 Watched today (auto — delete the section if empty)

```dataview
TABLE WITHOUT ID
  file.link AS "Video",
  channel AS "Channel",
  tl_dr_oneline AS "TL;DR"
FROM "<% P.youtube %>"
WHERE type = "youtube" AND watched_at = date(this.date)
SORT file.ctime ASC
```

## 💡 What I learned today (just one — or "nothing")

- 

## 🔗 Notes created today (auto)

```dataview
TABLE dateformat(file.ctime, "yyyy-MM-dd HH:mm") AS "Created"
FROM "<% P.root %>"
WHERE file.ctime >= date(this.date) AND file.ctime < date(this.date) + dur(1 day)
  AND file.name != this.file.name
  AND !contains(file.folder, "<% P.tpl %>")
SORT file.ctime DESC
LIMIT 20
```

---

## ⏮ Previous devlog

```dataview
LIST
FROM "<% P.devlog %>"
WHERE file.day < this.file.day AND file.day >= this.file.day - dur(7 days)
SORT file.day DESC
LIMIT 1
```
