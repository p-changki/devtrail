#!/usr/bin/env python3
"""DevTrail 대시보드 — 로컬 전용 HTTP 서버.

설계 원칙:
  - UI는 얇은 껍데기다. 로직은 전부 devtrail CLI에 있고 여기서는 호출만 한다.
  - 이 서버는 셸 명령을 실행한다. 따라서 보안을 기본값으로 잠근다:
      * 127.0.0.1 에만 바인딩 (외부 접근 불가)
      * 매 실행마다 랜덤 토큰 발급, 모든 API가 토큰 요구
      * Origin/Referer 가 자기 자신이 아니면 거부 (CSRF·DNS rebinding 방어)
      * 실행 가능한 명령을 화이트리스트로 고정 (임의 명령 실행 불가)
"""

import json
import os
import re
import secrets
import subprocess
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = Path(os.environ.get("DEVTRAIL_CONFIG", ""))
SCRIPTS = Path(os.environ.get("DEVTRAIL_SCRIPTS", ""))
DEVTRAIL_BIN = os.environ.get("DEVTRAIL_BIN", "devtrail")
TOKEN = os.environ.get("DEVTRAIL_TOKEN") or secrets.token_urlsafe(24)
HOST, PORT = "127.0.0.1", int(os.environ.get("DEVTRAIL_PORT", "7823"))

# 실행을 허용하는 명령. 여기 없는 것은 절대 실행하지 않는다.
ALLOWED_ACTIONS = {
    "activity": ["activity.sh"],
    "summary":  ["summary.sh"],
    "weekly":   ["weekly.sh"],
    "sync":     ["repodocs.sh"],
}
# HTTP로 받아들일 설정 키. 임의 키를 CLI로 흘려보내지 않기 위한 1차 방어다.
# 최종 권한은 CLI(`devtrail config set`)의 DT_SETTABLE_* 에 있다.
ALLOWED_TOGGLES = {
    "ai.summary_enabled",
    "backup.enabled",
    "linear.enabled",
}


def load_config():
    try:
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception:
        return {}


def dig(cfg, path, default=None):
    cur = cfg
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


def run(cmd, timeout=600):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return {"ok": p.returncode == 0, "code": p.returncode,
                "out": p.stdout, "err": p.stderr}
    except subprocess.TimeoutExpired:
        return {"ok": False, "code": -1, "out": "", "err": "시간 초과"}
    except FileNotFoundError as e:
        return {"ok": False, "code": -1, "out": "", "err": str(e)}


def today_str():
    return subprocess.run(["date", "+%Y-%m-%d"], capture_output=True,
                          text=True).stdout.strip()


def devlog_path(cfg, date):
    vault = dig(cfg, "vault.path", "")
    root = dig(cfg, "vault.root", "")
    dirname = dig(cfg, "dirs.devlog", "devlog")
    pat = dig(cfg, "naming.devlog_file", "{{DATE}} devlog.md")
    return Path(vault) / root / dirname / pat.replace("{{DATE}}", date)


def effective_toggles():
    """토글의 '실제로 적용되는 값'을 CLI에서 받아온다.

    설정 파일을 직접 읽으면 안 된다 — 키가 없을 때의 기본값이 셸과 달라지면
    화면에는 "꺼짐"인데 실제로는 켜져서 도는 상태가 된다(백업·AI 과금).
    기본값은 `devtrail config effective` 한 곳에만 있다.
    """
    r = run([DEVTRAIL_BIN, "config", "effective"], timeout=15)
    if r["ok"]:
        try:
            data = json.loads(r["out"])
            return {k: bool(data[k]) for k in sorted(ALLOWED_TOGGLES) if k in data}
        except (json.JSONDecodeError, TypeError):
            pass
    # 실패했으면 추측하지 않는다 — 틀린 상태를 보여주느니 모른다고 말한다.
    return {k: None for k in sorted(ALLOWED_TOGGLES)}


def build_status():
    cfg = load_config()
    date = today_str()
    log = devlog_path(cfg, date)
    text = log.read_text(encoding="utf-8") if log.exists() else ""

    # 표시용 집계. 판단 로직이 아니라 '무엇이 들어있나' 를 세는 것뿐이다.
    pr_rows = len(re.findall(r"^\| \[[^\]]*#\d+\]", text, re.M))
    summaries = len(re.findall(r"^> \[!abstract\]", text, re.M))
    has_activity = "devtrail:activity:start" in text

    launchd = run(["launchctl", "list"])
    loaded = [l for l in launchd["out"].splitlines() if "com.devtrail." in l]

    return {
        "date": date,
        "vault": dig(cfg, "vault.path", ""),
        "backend": dig(cfg, "vault.backend", "local"),
        "github_user": dig(cfg, "github.user", ""),
        "ai_provider": dig(cfg, "ai.provider", ""),
        "devlog": {
            "path": str(log),
            "exists": log.exists(),
            "has_activity": has_activity,
            "pr_rows": pr_rows,
            "summaries": summaries,
        },
        "toggles": effective_toggles(),
        "schedule": {
            "loaded": len(loaded),
            "labels": [l.split("\t")[-1] for l in loaded],
            "daily_hour": dig(cfg, "schedule.daily_hour", 10),
        },
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "DevTrail"

    def log_message(self, *a):  # 접근 로그로 콘솔을 더럽히지 않는다
        pass

    # ── 보안 ────────────────────────────────────────────────────────────────
    def _authorized(self, query):
        if query.get("token", [None])[0] != TOKEN:
            return False
        # CSRF: 다른 사이트가 이 로컬 서버를 호출하지 못하게 한다.
        origin = self.headers.get("Origin")
        if origin and origin not in (f"http://{HOST}:{PORT}",
                                     f"http://localhost:{PORT}"):
            return False
        host = (self.headers.get("Host") or "").split(":")[0]
        if host not in (HOST, "localhost"):
            return False
        return True

    def _send(self, code, body, ctype="application/json"):
        raw = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", f"{ctype}; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(raw)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    # ── 라우팅 ──────────────────────────────────────────────────────────────
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)

        if u.path == "/":
            if q.get("token", [None])[0] != TOKEN:
                return self._send(403, "토큰이 필요합니다. 터미널에 표시된 주소로 접속하세요.",
                                  "text/plain")
            html = (HERE / "index.html").read_text(encoding="utf-8")
            return self._send(200, html.replace("{{TOKEN}}", TOKEN), "text/html")

        if not self._authorized(q):
            return self._json(403, {"error": "unauthorized"})

        if u.path == "/api/status":
            return self._json(200, build_status())
        if u.path == "/api/doctor":
            r = run([DEVTRAIL_BIN, "doctor"], timeout=120)
            return self._json(200, {"text": r["out"] + r["err"]})
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if not self._authorized(q):
            return self._json(403, {"error": "unauthorized"})

        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or "{}")
        except json.JSONDecodeError:
            return self._json(400, {"error": "잘못된 JSON"})

        if u.path == "/api/action":
            name = body.get("action")
            if name not in ALLOWED_ACTIONS:
                return self._json(400, {"error": f"허용되지 않은 동작: {name}"})
            script = SCRIPTS / ALLOWED_ACTIONS[name][0]
            if not script.exists():
                return self._json(400, {"error": f"스크립트 없음: {script}"})
            env_date = body.get("date")
            cmd = [str(script)] + ([env_date] if _valid_date(env_date) else [])
            r = run(cmd)
            return self._json(200, r)

        if u.path == "/api/toggle":
            key, val = body.get("key"), body.get("value")
            if key not in ALLOWED_TOGGLES:
                return self._json(400, {"error": f"허용되지 않은 설정: {key}"})
            if not isinstance(val, bool):
                return self._json(400, {"error": "value는 true/false 여야 합니다"})
            return self._json(200, _write_toggle(key, val))

        return self._json(404, {"error": "not found"})


def _valid_date(s):
    return isinstance(s, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", s) is not None


def _write_toggle(key, val):
    """설정 쓰기는 반드시 `devtrail config set` 을 거친다.

    여기서 JSON을 직접 쓰면 허용 키·타입 검증·백업 규칙이 CLI와 갈라진다.
    읽기(effective_toggles)를 CLI로 옮겨놓고 쓰기만 직접 하면, 두 경로가
    서로 다른 규칙을 갖는 예전 상태로 되돌아간다.
    """
    r = run([DEVTRAIL_BIN, "config", "set", key, "true" if val else "false"],
            timeout=20)
    if not r["ok"]:
        msg = (r["err"] or r["out"] or "").strip()
        return {"ok": False, "err": msg or "설정 변경 실패"}
    return {"ok": True, "key": key, "value": val}


def main():
    if not CONFIG.is_file():
        print(f"설정을 찾을 수 없습니다: {CONFIG}", file=sys.stderr)
        return 1
    url = f"http://{HOST}:{PORT}/?token={TOKEN}"
    print(f"▶ DevTrail 대시보드\n  {url}\n  (Ctrl+C 로 종료)")
    if os.environ.get("DEVTRAIL_OPEN", "1") == "1":
        subprocess.Popen(["open", url])
    try:
        HTTPServer((HOST, PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\n종료했습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
