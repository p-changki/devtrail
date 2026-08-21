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
const folder = dtPath("weekly");
const iso = tp.date.now("gggg-[W]ww");
if (!app.vault.getAbstractFileByPath(folder)) await app.vault.createFolder(folder);
const target = `${folder}/${dtWeeklyName(iso)}.md`;
const existing = app.vault.getAbstractFileByPath(target);
if (existing) {
  const temp = app.workspace.getActiveFile();
  tp.hooks.on_all_templates_executed(async () => {
    await app.workspace.getLeaf(false).openFile(existing);
    if (temp && temp.path !== target) await app.vault.trash(temp, true);
  });
  return;
}
await tp.file.move(`${folder}/${dtWeeklyName(iso)}`);

// ⚠️ Dates are written into Dataview as literals.
//    Referencing frontmatter (this.period_start) reads as null and kills the
//    whole query with 'No implementation found for null + duration'.
//    The original vault's weekly reviews were catching nothing because of this.
const MON = tp.date.weekday("YYYY-MM-DD", 1);
const SUN = tp.date.weekday("YYYY-MM-DD", 7);
const NEXT = tp.date.weekday("YYYY-MM-DD", 8);
const P = { root: DT.root || "", devlog: dtPath("devlog"), inbox: dtPath("inbox"),
            repodocs: dtPath("repodocs"), tpl: dtTplFolder() };
-%>
---
tags:
  - type/weekly-review
type: weekly-review
week: <% iso %>
period_start: <% MON %>
period_end: <% SUN %>
created: <% tp.date.now("YYYY-MM-DD") %>
updated: <% tp.date.now("YYYY-MM-DD") %>
---

# 📅 Weekly review <% iso %>

Period: <% MON %> – <% SUN %>

## ⚡ Five-minute version (if that is all you have)

### This week in one line
> 

### One thing for next week
> 

---

## 📊 Automatic

### This week's devlogs

```dataview
LIST
FROM "<% P.devlog %>"
WHERE file.day >= date("<% MON %>") AND file.day <= date("<% SUN %>")
SORT file.day ASC
```

### Notes created this week

```dataview
TABLE WITHOUT ID file.link AS "Note", file.folder AS "Where"
FROM "<% P.root %>"
WHERE file.ctime >= date("<% MON %>") AND file.ctime < date("<% NEXT %>")
  AND !contains(file.folder, "<% P.tpl %>")
SORT file.ctime DESC
LIMIT 30
```

### Inbox left over (oldest first)

```dataview
TABLE (date(today) - file.ctime).day AS "Days"
FROM "<% P.inbox %>"
WHERE file.name != "_index"
SORT file.ctime ASC
```

---

## 🧭 Theme and learning

### Main theme
- 

### What I learned
- 

## 🎯 Three notes worth revisiting

1. [[ ]]
2. [[ ]]
3. [[ ]]

## 🚧 Unfinished

- [ ] 

## 🎯 Focus next week (one or two)

- 

---

## 🔄 PKM health check

- [ ] Inbox under 20
- [ ] At least one zettel promoted
- [ ] At least one MOC updated
- [ ] No gaps in the devlog
