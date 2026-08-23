'use strict';
/* Obsidian 의 DOM 헬퍼를 최소한으로 흉내 낸다.
 *
 * ⚠️ 이걸 만든 이유: view.js 를 **실제로 실행하는** 테스트가 없어서, 정의도
 *    주입도 안 된 이름을 세 번 연속 놓쳤다(require('obsidian') · RM 참조 ·
 *    daysBetween). 전부 테스트는 녹색이었고 실물에서만 드러났다.
 *
 * ⚠️ 진짜 DOM 이 아니다. 픽셀도 레이아웃도 검증하지 못한다. 여기서 잡는 것은
 *    "부르면 죽는가" 하나다 — 그것만으로도 위 셋을 다 잡는다.
 */
function el(tag) {
  const node = {
    tag,
    children: [],
    attrs: {},
    classes: new Set(),
    style: {},
    text: '',
    disabled: false,
    value: '',
    createEl(t, opts) {
      const c = el(t);
      if (opts && opts.text !== undefined) c.text = String(opts.text);
      if (opts && opts.cls) String(opts.cls).split(/\s+/).forEach((x) => x && c.classes.add(x));
      node.children.push(c);
      return c;
    },
    createDiv(opts) { return node.createEl('div', opts); },
    createSpan(opts) { return node.createEl('span', opts); },
    setText(t) { node.text = String(t); },
    setAttr(k, v) { node.attrs[k] = v; },
    getAttr(k) { return node.attrs[k]; },
    addClass(c) { node.classes.add(c); },
    removeClass(c) { node.classes.delete(c); },
    hasClass(c) { return node.classes.has(c); },
    empty() { node.children.length = 0; },
    addEventListener() {},
    querySelector(sel) {
      const want = sel.replace(/^\./, '');
      const walk = (n) => {
        for (const c of n.children) {
          if (c.classes.has(want) || c.tag === sel) return c;
          const found = walk(c);
          if (found) return found;
        }
        return null;
      };
      return walk(node);
    },
    querySelectorAll() { return []; },
    focus() {},
  };
  return node;
}

/* 렌더 결과를 훑는다 — 무엇이 그려졌는지 세기 위해. */
function collectText(node, out) {
  out = out || [];
  if (node.text) out.push(node.text);
  for (const c of node.children) collectText(c, out);
  return out;
}

function collectClasses(node, out) {
  out = out || new Set();
  for (const c of node.classes) out.add(c);
  for (const c of node.children) collectClasses(c, out);
  return out;
}

module.exports = { el, collectText, collectClasses };
