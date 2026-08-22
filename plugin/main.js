'use strict';

/*
 * DevTrail Command Center — Phase 1 골격.
 *
 * 이 플러그인은 읽기 모델이자 상호작용 계층이다. 경로·설정·쓰기의 두 번째
 * 출처가 되어서는 안 된다.
 *
 * ⚠️ 경로는 _devtrail-paths.md 하나에서만 읽는다.
 *
 *    이 저장소는 2026-08-22 에 같은 결함을 세 번 고쳤다 — 생성 스크립트,
 *    웹 대시보드, 메뉴바 앱이 각자 dirs.devlog 의 기본값을 갖고 있었다.
 *    셋 다 새로 설치한 볼트에서 "파일이 있는데 없다" 고 말했다.
 *    이 플러그인은 네 번째 소비자다. 짐작하지 않는다.
 *
 * ⚠️ devtrail.config.json 을 읽지 않는다. 경로 맵이 없거나 깨졌으면
 *    추측하는 대신 무엇을 실행해야 하는지 알려준다.
 *
 * 빌드 도구를 쓰지 않는다(ADR 0002 D3). 이 파일이 곧 배포물이다.
 */

const obsidian = require('obsidian');

const VIEW_TYPE = 'devtrail-command-center';
const PATH_MAP_FILE = '_devtrail-paths.md';

/* ── 경로 맵 ──────────────────────────────────────────────────────────────
 *
 * DevTrail CLI 가 템플릿 폴더에 만드는 노트다. 안에 json 코드블록이 하나
 * 있고, 거기에 볼트의 모든 경로·프로젝트·언어가 들어 있다.
 * 노트 템플릿들도 같은 파일을 읽는다 — 그래서 출처가 하나다.
 */
async function readPathMap(app) {
  const file = app.vault.getFiles().find((f) => f.name === PATH_MAP_FILE);
  if (!file) return { ok: false, reason: 'missing' };
  try {
    const raw = await app.vault.read(file);
    const m = raw.match(/```json\s*([\s\S]*?)```/);
    if (!m) return { ok: false, reason: 'malformed' };
    const data = JSON.parse(m[1]);
    if (!data || typeof data.paths !== 'object') {
      return { ok: false, reason: 'malformed' };
    }
    return { ok: true, data };
  } catch (e) {
    return { ok: false, reason: 'malformed' };
  }
}

/* 화면 문구. 한국어·영어만 있고, 그 외에는 한국어로 떨어진다 —
 * CLI 의 dt_lang 과 같은 규칙이다. */
const TEXT = {
  ko: {
    title: 'DevTrail',
    loading: '읽는 중…',
    missing: 'DevTrail 경로 맵을 찾지 못했습니다',
    missingHelp: '터미널에서 devtrail obsidian 을 한 번 실행하세요.',
    malformed: '경로 맵을 읽지 못했습니다',
    malformedHelp: '터미널에서 devtrail doctor 로 확인하세요.',
    ready: '준비됐습니다',
    readyHelp: '화면은 다음 단계에서 만듭니다.',
    vaultRoot: '루트',
    projects: '프로젝트',
  },
  en: {
    title: 'DevTrail',
    loading: 'Reading…',
    missing: 'Could not find the DevTrail path map',
    missingHelp: 'Run devtrail obsidian once in a terminal.',
    malformed: 'Could not read the path map',
    malformedHelp: 'Check it with devtrail doctor in a terminal.',
    ready: 'Ready',
    readyHelp: 'The screens come in the next step.',
    vaultRoot: 'Root',
    projects: 'Projects',
  },
};

function textFor(lang) {
  return TEXT[lang === 'en' ? 'en' : 'ko'];
}

class CommandCenterView extends obsidian.ItemView {
  getViewType() { return VIEW_TYPE; }
  getDisplayText() { return 'DevTrail'; }
  getIcon() { return 'layout-dashboard'; }

  async onOpen() {
    await this.render();
  }

  async render() {
    const root = this.contentEl;
    root.empty();
    root.addClass('devtrail-command-center');

    const map = await readPathMap(this.app);
    const t = textFor(map.ok ? map.data.lang : 'ko');

    const head = root.createEl('div', { cls: 'devtrail-cc-header' });
    head.createEl('h2', { text: t.title });

    if (!map.ok) {
      // ⚠️ 여기서 경로를 짐작하지 않는다. 무엇을 실행해야 하는지 말한다.
      const box = root.createEl('div', { cls: 'devtrail-cc-recovery' });
      const isMissing = map.reason === 'missing';
      box.createEl('p', { text: isMissing ? t.missing : t.malformed });
      box.createEl('p', {
        text: isMissing ? t.missingHelp : t.malformedHelp,
        cls: 'devtrail-cc-muted',
      });
      return;
    }

    const body = root.createEl('div', { cls: 'devtrail-cc-body' });
    body.createEl('p', { text: t.ready });
    body.createEl('p', { text: t.readyHelp, cls: 'devtrail-cc-muted' });

    const facts = body.createEl('ul');
    facts.createEl('li', { text: `${t.vaultRoot}: ${map.data.root || '/'}` });
    const projects = Array.isArray(map.data.projects) ? map.data.projects : [];
    facts.createEl('li', { text: `${t.projects}: ${projects.length}` });
  }
}

module.exports = class DevTrailCommandCenter extends obsidian.Plugin {
  async onload() {
    this.registerView(VIEW_TYPE, (leaf) => new CommandCenterView(leaf));

    this.addRibbonIcon('layout-dashboard', 'DevTrail', () => this.activate());
    this.addCommand({
      id: 'open',
      name: 'Open DevTrail Command Center',
      callback: () => this.activate(),
    });
  }

  onunload() {
    // ⚠️ 열려 있던 뷰를 정리한다. 남겨두면 플러그인을 끈 뒤에도 빈 탭이 남는다.
    this.app.workspace.detachLeavesOfType(VIEW_TYPE);
  }

  async activate() {
    const { workspace } = this.app;
    const existing = workspace.getLeavesOfType(VIEW_TYPE);
    if (existing.length > 0) {
      workspace.revealLeaf(existing[0]);
      return;
    }
    const leaf = workspace.getRightLeaf(false);
    if (!leaf) return;
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    workspace.revealLeaf(leaf);
  }
};
