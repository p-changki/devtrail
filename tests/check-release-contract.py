#!/usr/bin/env python3
"""릴리즈에 함께 나가는 것들이 서로 맞는가 (ADR 0006 M6).

⚠️ 왜 이 파일이 생겼나

DMG 하나에 앱 · 헬퍼 · 번들 jq · 플러그인 · 템플릿 · 설정 스키마가 함께
들어간다. 이것들이 **따로 움직이면** 사용자 볼트가 조용히 어긋난다 —
앱이 설정 스키마 v3 를 쓰는데 템플릿이 v4 를 가정하는 식이다.

이 저장소는 dirs.devlog 기본값을 네 곳에 두고 같은 결함을 **네 번** 고쳤다.
문서에 적어두는 것으로는 막지 못했다. 게이트가 소비해야 막힌다.

⚠️ 여기서 보는 것은 **일치**다. 값이 옳은지는 각 정본이 정한다:

    VERSION            제품 버전
    plugin/manifest.json  플러그인 버전
    plugin/files.json     배포 파일 목록
    lib/migrate.sh        DT_SCHEMA (설정 스키마)
    app/Package.swift     최소 macOS
    CHANGELOG.md          이 버전의 항목

⚠️ release.json 은 **빌드 산출물**이다. 있으면 위 정본들과 대조하고,
   없으면 만들 수 있는지만 본다 — 저장소에 커밋하지 않는다.
"""
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text(encoding="utf-8")


def load_json(p):
    return json.loads(read(p))


def main():
    bad = []

    # ── 정본들 ──────────────────────────────────────────────────────────────
    try:
        version = read("VERSION").strip()
    except OSError:
        print("❌ VERSION 을 읽을 수 없습니다")
        return 1
    if not re.match(r"^\d+\.\d+\.\d+", version):
        bad.append("VERSION 이 유의적 버전이 아닙니다: %s" % version)

    try:
        manifest = load_json("plugin/manifest.json")
    except (OSError, ValueError) as e:
        print("❌ plugin/manifest.json 을 읽을 수 없습니다: %s" % e)
        return 1
    plugin_ver = manifest.get("version", "")
    if not re.match(r"^\d+\.\d+\.\d+", str(plugin_ver)):
        bad.append("플러그인 버전이 유의적 버전이 아닙니다: %s" % plugin_ver)

    try:
        files = load_json("plugin/files.json").get("files", [])
    except (OSError, ValueError) as e:
        print("❌ plugin/files.json 을 읽을 수 없습니다: %s" % e)
        return 1

    m = re.search(r"^DT_SCHEMA=(\d+)", read("lib/migrate.sh"), re.M)
    if not m:
        bad.append("lib/migrate.sh 에서 DT_SCHEMA 를 읽을 수 없습니다")
        schema = None
    else:
        schema = int(m.group(1))

    m = re.search(r"macOS\(\.v(\d+)\)", read("app/Package.swift"))
    if not m:
        bad.append("app/Package.swift 에서 최소 macOS 를 읽을 수 없습니다")
        min_macos = None
    else:
        min_macos = m.group(1)

    # ── ① files.json 이 선언한 파일이 실제로 있는가 ─────────────────────────
    #
    # ⚠️ 없는 파일을 매니페스트에 적으면, 설치본에 빠진 채로 나간다.
    for f in files:
        if not (ROOT / "plugin" / f).is_file():
            bad.append("files.json 이 없는 파일을 가리킵니다: plugin/%s" % f)

    # ② 선언하지 않은 파일이 plugin/ 에 있는가
    #
    # ⚠️ 선언 밖의 파일은 설치되지 않는다. 있으면 개발자만 보고 사용자는
    #    못 보는 코드가 생긴다 — 그 상태로 "동작한다" 고 말하게 된다.
    declared = set(files)
    for p in sorted((ROOT / "plugin").iterdir()):
        if p.is_file() and p.name not in declared:
            bad.append("plugin/%s 이 files.json 에 없습니다" % p.name)

    # ── ③ 설정 스키마의 정본이 하나인가 ─────────────────────────────────────
    #
    # ⚠️ init 이 쓰는 값과 DT_SCHEMA 가 어긋나면, 새로 만든 설정이 곧바로
    #    "마이그레이션 필요" 상태가 된다.
    if schema is not None:
        w = read("lib/init/write.sh")
        for mm in re.finditer(r"^\s*version:\s*(\d+),", w, re.M):
            if int(mm.group(1)) != schema:
                bad.append("lib/init/write.sh 의 version: %s 가 DT_SCHEMA=%d 와 다릅니다"
                           % (mm.group(1), schema))

    # ── ④ CHANGELOG 에 이 버전이 있는가 ─────────────────────────────────────
    try:
        if not re.search(r"^## \[%s\]" % re.escape(version), read("CHANGELOG.md"), re.M):
            bad.append("CHANGELOG.md 에 [%s] 항목이 없습니다" % version)
    except OSError:
        bad.append("CHANGELOG.md 를 읽을 수 없습니다")

    # ── ⑤ 매니페스트를 실제로 만들 수 있는가 ────────────────────────────────
    #
    # ⚠️ "만들 수 있다" 를 문서로 주장하지 않는다. 만들어 본다.
    tmp = ROOT / ".release-contract-check.json"
    try:
        r = subprocess.run(
            [str(ROOT / "scripts/make-release-manifest.sh"), str(tmp)],
            capture_output=True, text=True, cwd=str(ROOT))
        if r.returncode != 0:
            bad.append("릴리즈 매니페스트를 만들지 못합니다: %s"
                       % (r.stderr.strip() or r.stdout.strip())[:200])
        else:
            rel = json.loads(tmp.read_text(encoding="utf-8"))
            # 만든 것이 정본과 같은가
            if rel.get("version") != version:
                bad.append("매니페스트 version=%s · VERSION=%s"
                           % (rel.get("version"), version))
            if rel.get("plugin", {}).get("version") != plugin_ver:
                bad.append("매니페스트 plugin.version=%s · manifest.json=%s"
                           % (rel.get("plugin", {}).get("version"), plugin_ver))
            if schema is not None and rel.get("config_schema") != schema:
                bad.append("매니페스트 config_schema=%s · DT_SCHEMA=%d"
                           % (rel.get("config_schema"), schema))
            if min_macos is not None \
                    and rel.get("app", {}).get("min_macos") != min_macos:
                bad.append("매니페스트 min_macos=%s · Package.swift=%s"
                           % (rel.get("app", {}).get("min_macos"), min_macos))
            arts = rel.get("artifacts", [])
            if len(arts) != len(files):
                bad.append("매니페스트 배포물 %d개 · files.json %d개"
                           % (len(arts), len(files)))
            # ⚠️ 해시가 실제 파일과 맞는가. 매니페스트만 갱신하고 파일을 안
            #    바꾸는(또는 그 반대) 사고를 여기서 잡는다.
            import hashlib
            for a in arts:
                p = ROOT / a.get("path", "")
                if not p.is_file():
                    bad.append("매니페스트가 없는 파일을 가리킵니다: %s" % a.get("path"))
                    continue
                h = hashlib.sha256(p.read_bytes()).hexdigest()
                if h != a.get("sha256"):
                    bad.append("%s 의 sha256 이 매니페스트와 다릅니다" % a.get("path"))
    except Exception as e:  # noqa: BLE001
        bad.append("매니페스트 검사 중 오류: %s" % e)
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass

    # ── ⑥ 매니페스트는 커밋되지 않는다 ──────────────────────────────────────
    #
    # ⚠️ 빌드 산출물이 저장소에 들어오면, 손으로 고친 것과 만든 것을
    #    구별할 수 없게 된다.
    r = subprocess.run(["git", "ls-files", "release.json"],
                       capture_output=True, text=True, cwd=str(ROOT))
    if r.stdout.strip():
        bad.append("release.json 이 커밋돼 있습니다 — 빌드 산출물은 추적하지 않습니다")

    if bad:
        print("❌ 릴리즈 계약이 어긋납니다")
        for b in bad:
            print("   - %s" % b)
        return 1

    print("✅ 릴리즈 계약 일치 — v%s · 플러그인 %s · 스키마 v%s · 최소 macOS %s · 파일 %d개"
          % (version, plugin_ver, schema, min_macos, len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
