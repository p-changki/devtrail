<%*
// ── DevTrail 공통 헬퍼 ───────────────────────────────────────────────────────
// 모든 템플릿 맨 위에 붙는다. 경로를 하드코딩하지 않기 위한 장치다.
//
// 경로 맵 노트를 '파일명'으로 찾는다. 어디에 있든 찾으므로 템플릿에
// 볼트 경로가 한 글자도 들어가지 않는다.
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

// 경로 조회. 맵이 없으면 fallback 을 쓴다 — 템플릿이 죽지 않게.
const dtPath = (key, fallback) => (DT.paths && DT.paths[key]) || fallback || "";

// 파일명에 쓸 수 없는 문자를 정리한다.
const dtSafe = (s) => (s || "").replace(/[\\/:*?"<>|#\[\]]/g, "-").replace(/\s+/g, " ").trim();

// 같은 이름이 있으면 -1, -2 를 붙인다. 덮어쓰지 않는다.
const dtUnique = (folder, base) => {
  let name = base, i = 1;
  while (app.vault.getAbstractFileByPath(`${folder}/${name}.md`)) name = `${base}-${i++}`;
  return name;
};

// 취소했을 때 빈 고아 노트가 남지 않게 정리한다.
const dtCancel = (file) => {
  tp.hooks.on_all_templates_executed(async () => {
    if (file) await app.vault.trash(file, true);
  });
};

// 설정에서 프로젝트 목록을 읽는다. 없으면 직접 입력받는다.
// (원본은 PROJECTS 배열을 JS 안에 박아뒀다 — 프로젝트가 늘 때마다 템플릿을 고쳐야 했다)
const dtProjects = () => (DT.projects && DT.projects.length ? DT.projects : []);
_%>
<%*
const folder = dtPath("moc");
const raw = (await tp.system.prompt("MOC 주제 (예: RAG)"))?.trim();
if (!raw) { dtCancel(app.workspace.getActiveFile()); tR = ""; return; }
const topic = dtSafe(raw);
const slug = topic.toLowerCase().replace(/\s+/g, "-");
if (!app.vault.getAbstractFileByPath(folder)) await app.vault.createFolder(folder);
await tp.file.move(`${folder}/${dtUnique(folder, `${topic} MOC`)}`);
tR += `---
tags:
  - type/moc
  - 주제/${slug}
type: moc
scope: topic
status: active
created: ${tp.date.now("YYYY-MM-DD")}
updated: ${tp.date.now("YYYY-MM-DD")}
topic: ${slug}
review_at:
---

# 🗺 ${topic} MOC

> 이 주제의 허브. 관련 노트로 들어가는 입구다.

## 🎯 이 주제가 뭔가

## 🌱 학습 로드맵

- [ ] 기초:
- [ ] 중급:
- [ ] 고급:

## 🔗 같은 주제 노트 (자동 집계)

\`\`\`dataview
TABLE status AS "숙성도", file.mtime AS "수정"
FROM #주제/${slug}
WHERE file.path != this.file.path
SORT file.mtime DESC
\`\`\`

## 💡 열린 질문

- 

## 🔗 관련 MOC

- [[ ]]
`;
%>
