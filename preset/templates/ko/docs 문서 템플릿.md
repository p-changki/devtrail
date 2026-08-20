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

// 개발일지 파일명. 설정의 naming.devlog_file 을 따른다.
// ⚠️ 여기를 박아두면 devtrail activity 가 만드는 파일과 다른 파일이 생긴다.
const dtDevlogName = (date) => {
  const pat = (DT.naming && DT.naming.devlog_file) || "{{DATE}} devlog.md";
  return pat.replace("{{DATE}}", date).replace(/\.md$/, "");
};

// 템플릿 폴더 이름. 쿼리의 제외 조건에 쓴다.
const dtTplFolder = () => ((DT.paths && DT.paths.templates) || "Templates").split("/").pop();

// 태그 네임스페이스. 사용자가 손으로 붙이는 두 가지만 언어를 탄다.
const dtNs = (k) => (DT.ns && DT.ns[k]) || k;

// 주간리뷰 파일명. 설정의 naming.weekly_file 을 따른다.
const dtWeeklyName = (iso) => {
  const pat = (DT.naming && DT.naming.weekly_file) || "{{ISOWEEK}} weekly.md";
  return pat.replace("{{ISOWEEK}}", iso).replace(/\.md$/, "");
};
_%>
<%*
const root = dtPath("projects");
const rootFolder = app.vault.getAbstractFileByPath(root);
if (!rootFolder || !rootFolder.children) {
  tR = `# ⚠️ 프로젝트 폴더를 찾을 수 없습니다: ${root}`; return;
}
const projects = rootFolder.children.filter(f => f.children).map(f => f.name).sort();
if (!projects.length) {
  tR = "# ⚠️ 프로젝트가 없습니다. 먼저 '프로젝트 생성 템플릿'으로 만드세요."; return;
}
const project = await tp.system.suggester(projects, projects, false, "📁 어느 프로젝트?");
if (!project) { dtCancel(app.workspace.getActiveFile()); tR = ""; return; }

const types = ["design — 설계안", "prd — 요구사항", "architecture — 아키텍처",
               "tech — 기술조사", "decision — 의사결정(ADR)", "meeting — 회의록"];
const values = ["design", "prd", "architecture", "tech", "decision", "meeting"];
const docType = await tp.system.suggester(types, values, false, "📄 문서 종류?");
if (!docType) { dtCancel(app.workspace.getActiveFile()); tR = ""; return; }

const title = (await tp.system.prompt("📝 문서 제목"))?.trim();
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

## 🎯 개요 (한 줄)

- 

## 📋 배경 / 문제

- 

## 🧩 내용 / 설계

- 

## ⚖️ 대안 / 트레이드오프

- 

## ✅ 결정

- 

## 🔗 관련 문서

- 
`;
%>
