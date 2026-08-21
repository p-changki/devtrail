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
const folder = dtPath("monthly");
const ym = tp.date.now("YYYY-MM");
if (!app.vault.getAbstractFileByPath(folder)) await app.vault.createFolder(folder);
const target = `${folder}/${ym} monthly.md`;
if (app.vault.getAbstractFileByPath(target)) {
  const temp = app.workspace.getActiveFile();
  tp.hooks.on_all_templates_executed(async () => {
    await app.workspace.getLeaf(false).openFile(app.vault.getAbstractFileByPath(target));
    if (temp && temp.path !== target) await app.vault.trash(temp, true);
  });
  return;
}
await tp.file.move(`${folder}/${ym} monthly`);
const FROM = `${ym}-01`;
const P = { root: DT.root || "", weekly: dtPath("weekly"), inbox: dtPath("inbox"),
            zettel: dtPath("zettel"), mat: dtNs("maturity") };
-%>
---
tags:
  - type/monthly-review
type: monthly-review
month: <% ym %>
created: <% tp.date.now("YYYY-MM-DD") %>
updated: <% tp.date.now("YYYY-MM-DD") %>
---

# 📆 Monthly review <% ym %>

## 🔗 This month's weekly reviews

```dataview
LIST
FROM "<% P.weekly %>"
WHERE file.ctime >= date("<% FROM %>") AND file.ctime < date("<% FROM %>") + dur(1 month)
SORT file.ctime ASC
```

## 🏆 Promoted to evergreen this month

```dataview
LIST
FROM "<% P.zettel %>"
WHERE contains(file.tags, "<% P.mat %>/evergreen")
  AND file.mtime >= date("<% FROM %>") AND file.mtime < date("<% FROM %>") + dur(1 month)
SORT file.mtime DESC
```

## 📥 Inbox backlog (30+ days)

```dataview
TABLE (date(today) - file.ctime).day AS "Days"
FROM "<% P.inbox %>"
WHERE file.name != "_index" AND file.ctime <= date(today) - dur(30 days)
SORT file.ctime ASC
```

## 🎯 Looking back

### Top 3 things I learned
1. 
2. 
3. 

### Wins
- 

### What to improve
- 

## 🚀 Focus next month

-
