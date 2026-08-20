<%*
// ── DevTrail shared helpers ─────────────────────────────────────────────────
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
_%>
<%*
const root = dtPath("projects");
const rootFolder = app.vault.getAbstractFileByPath(root);
if (!rootFolder || !rootFolder.children) {
  tR = `# ⚠️ Project folder not found: ${root}`; return;
}
const projects = rootFolder.children.filter(f => f.children).map(f => f.name).sort();
if (!projects.length) {
  tR = "# ⚠️ No projects yet. Create one with the 'New project' template first."; return;
}
const project = await tp.system.suggester(projects, projects, false, "📁 Which project?");
if (!project) { dtCancel(app.workspace.getActiveFile()); tR = ""; return; }

const types = ["design — design proposal", "prd — requirements", "architecture — architecture",
               "tech — technical research", "decision — decision record (ADR)", "meeting — meeting notes"];
const values = ["design", "prd", "architecture", "tech", "decision", "meeting"];
const docType = await tp.system.suggester(types, values, false, "📄 What kind of doc?");
if (!docType) { dtCancel(app.workspace.getActiveFile()); tR = ""; return; }

const title = (await tp.system.prompt("📝 Document title"))?.trim();
if (!title) { dtCancel(app.workspace.getActiveFile()); tR = ""; return; }

const today = tp.date.now("YYYY-MM-DD");
const docs = `${root}/${project}/docs`;
if (!app.vault.getAbstractFileByPath(docs)) await app.vault.createFolder(docs);
await tp.file.move(`${docs}/${dtUnique(docs, `${today} ${dtSafe(title)}`)}`);

tR += `---
tags:
  - type/doc
  - doc/${docType}
  - project/${project}
  - area/dev
type: doc
doc_type: ${docType}
status: draft
created: ${today}
updated: ${today}
project: ${project}
review_at:
---

# ${title}

> 📁 [[${root}/${project}/README|${project}]] · 📄 ${docType} · 🗓 ${today}

## 🎯 Summary (one line)

- 

## 📋 Background / problem

- 

## 🧩 Design

- 

## ⚖️ Alternatives and trade-offs

- 

## ✅ Decision

- 

## 🔗 Related documents

- 
`;
%>
