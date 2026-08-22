#!/usr/bin/env python3
"""볼트를 읽어 상태를 JSON 으로 낸다. Obsidian 이 꺼져 있어도 답한다.

⚠️ 집계 규칙은 plugin/main.js 의 collect() 에도 있다. 두 벌이다.
   플러그인이 CLI 를 부르게 하려면 Obsidian 안에서 shell commands 를 거쳐야
   해 느리고 취약하다. 그래서 두 벌을 두되, tests/test-snapshot.sh 가 같은
   볼트에서 두 구현을 **실제로 돌려 비교**한다. 어긋나면 빨간불이다.

   이 저장소는 dirs.devlog 의 기본값을 네 곳이 각자 가져 같은 결함을 네 번
   고쳤다. 두 벌을 허용하는 이 결정은 그 계약 테스트가 있는 동안에만 유효하다
   (ADR 0003).

⚠️ 읽기만 한다. 파일을 만들거나 고치지 않는다.
"""
import io
import json
import os
import re
import sys
import time

# frontmatter 는 앞머리의 --- 블록 하나뿐이다. 본문 중간의 --- 는 구분선이다.
_FM = re.compile(r'\A---\r?\n(.*?)\r?\n---\r?\n', re.S)


def read_frontmatter(path):
    """필요한 스칼라 키만 읽는다.

    ⚠️ YAML 파서를 쓰지 않는다 — 의존성을 늘리지 않으려는 것도 있지만,
       Obsidian 이 읽는 것과 다르게 해석할 위험이 더 크다. 우리가 보는 키는
       전부 한 줄 스칼라이므로 그만 읽는다. 리스트(tags)는 보지 않는다.
    """
    try:
        with io.open(path, encoding='utf-8') as f:
            head = f.read(4096)
    except (OSError, UnicodeDecodeError):
        return {}
    m = _FM.match(head)
    if not m:
        return {}
    out = {}
    for line in m.group(1).split('\n'):
        if line[:1] in (' ', '\t', '-') or ':' not in line:
            continue
        k, _, v = line.partition(':')
        v = v.strip()
        # 따옴표는 벗긴다. Obsidian 도 그렇게 읽는다.
        if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
            v = v[1:-1]
        out[k.strip()] = v
    return out


def is_user_note(rel, templates_rel):
    """플러그인의 isUserNote 와 같은 규칙."""
    name = os.path.basename(rel)
    if name.startswith('_'):
        return False
    if templates_rel and (rel == templates_rel or rel.startswith(templates_rel + '/')):
        return False
    return True


def walk(root, templates_rel):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fn in files:
            if not fn.endswith('.md'):
                continue
            full = os.path.join(base, fn)
            rel = os.path.relpath(full, root)
            if not is_user_note(rel, templates_rel):
                continue
            yield full, rel


def collect(root, templates_rel, today, now_ms, limit=5):
    projects, inbox, overdue, trouble, recent = [], [], [], [], []
    week_ago = now_ms - 7 * 24 * 60 * 60 * 1000
    this_week = 0
    total = 0

    for full, rel in walk(root, templates_rel):
        try:
            st = os.stat(full)
        except OSError:
            continue
        total += 1
        mtime = int(st.st_mtime * 1000)
        # macOS 는 birthtime 이 있다. 없으면 ctime 을 쓴다 — 플러그인의
        # f.stat.ctime 과 같은 자리다.
        ctime = int(getattr(st, 'st_birthtime', st.st_ctime) * 1000)
        if ctime >= week_ago:
            this_week += 1

        meta = read_frontmatter(full)
        t = meta.get('type')
        name = os.path.basename(rel)[:-3]

        if t == 'project-home' and meta.get('status') == 'active':
            projects.append({
                'name': meta.get('project') or os.path.basename(os.path.dirname(rel)) or name,
                'stage': meta.get('stage') or None,
                'next_action': meta.get('next_action') or None,
                'path': rel,
                'mtime': mtime,
            })
        if t in ('trouble', 'troubleshooting'):
            trouble.append({'path': rel, 'mtime': mtime})
        if meta.get('status') == 'inbox':
            inbox.append({'title': name, 'path': rel,
                          'created': meta.get('created') or None, 'mtime': mtime})
        ra = meta.get('review_at')
        if ra and str(ra)[:10] <= today:
            overdue.append({'path': rel, 'at': str(ra)[:10]})
        recent.append({'title': name, 'type': t or None, 'path': rel, 'mtime': mtime})

    projects.sort(key=lambda p: -p['mtime'])
    inbox.sort(key=lambda i: i['mtime'])          # 오래된 것 먼저
    overdue.sort(key=lambda o: o['at'])
    recent.sort(key=lambda r: -r['mtime'])

    return {
        'projects': projects, 'inbox': inbox, 'overdue': overdue,
        'trouble': trouble, 'recent': recent[:10],
        'this_week': this_week, 'total': total, 'limit': limit,
    }


def open_tasks(path):
    """미완료이고 **내용이 있는** 체크박스만.

    ⚠️ 템플릿은 '- [ ]' 를 자리표시로 넣는다. 그것을 세면 아무것도 안 쓴 날에
       '할 일 3개' 라고 말하게 된다. 플러그인의 openTasks 와 같은 규칙이다.
    """
    try:
        with io.open(path, encoding='utf-8') as f:
            raw = f.read()
    except OSError:
        return 0
    n = 0
    for line in raw.split('\n'):
        m = re.match(r'^\s*- \[ \]\s*(.*)$', line)
        if m and m.group(1).strip():
            n += 1
    return n


def main():
    cfg = json.loads(sys.argv[1])
    root = cfg['root']
    limit = int(cfg.get('limit', 5))
    today = cfg.get('today') or time.strftime('%Y-%m-%d')
    now_ms = int(time.time() * 1000)

    if not os.path.isdir(root):
        # ⚠️ 없는 것을 0 으로 말하지 않는다. 세어 본 적이 없는 것과 세어 보니
        #    0 인 것은 다른 사실이다.
        json.dump({'available': False}, sys.stdout, ensure_ascii=False)
        return

    c = collect(root, cfg.get('templates_rel') or '', today, now_ms, limit)
    devlog = cfg.get('devlog_path') or ''
    exists = bool(devlog) and os.path.isfile(devlog)

    out = {
        'available': True,
        'today': {
            'date': today,
            'devlog_exists': exists,
            'open_tasks': open_tasks(devlog) if exists else ('unknown' if not devlog else 0),
            # ⚠️ 경로를 돌려준다. 앱이 파일명 규칙을 한 벌 더 갖지 않게 —
            #    그 순간 규칙이 갈리고 "있는데 없다" 는 화면이 생긴다.
            'devlog_path': devlog or None,
        },
        'projects': {
            'active_count': len(c['projects']),
            'next_actions': [
                {'project': p['name'], 'next_action': p['next_action'], 'stage': p['stage']}
                for p in c['projects'][:limit] if p['next_action']
            ],
        },
        'inbox': {
            'count': len(c['inbox']),
            'oldest_at': (c['inbox'][0].get('created')
                          or time.strftime('%Y-%m-%d', time.localtime(c['inbox'][0]['mtime'] / 1000))
                          ) if c['inbox'] else None,
            'preview': [{'title': i['title'], 'path': i['path']} for i in c['inbox'][:limit]],
        },
        'notes': {
            'total': c['total'],
            'this_week': c['this_week'],
            'trouble': len(c['trouble']),
            'overdue': len(c['overdue']),
        },
        'recent': [{'title': r['title'], 'type': r['type'], 'path': r['path']}
                   for r in c['recent'][:limit]],
    }
    json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == '__main__':
    main()
