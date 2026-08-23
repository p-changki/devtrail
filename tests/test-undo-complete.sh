#!/usr/bin/env bash
# undo 가 **정말로** 원래대로 되돌리는가 (ADR 0006 · 2026-08-24 실물 QA).
#
# ⚠️ 왜 이 시험이 생겼나
#
#    사용자의 실제 iCloud 볼트에 셋업을 적용한 뒤 `devtrail undo` 를 돌렸는데,
#    **템플릿 22개가 그대로 남았다.** 저널에 기록되지 않았기 때문이다
#    (`lib/merge/templates.sh` 가 cp 만 하고 jr_created 를 안 불렀다).
#
#    "되돌릴 수 있습니다" 는 이 프로젝트가 사용자에게 하는 약속이다. 저널에
#    빠진 쓰기가 하나라도 있으면 그 약속이 깨진다. 그런데 **코드를 읽어서는
#    빠진 것을 찾기 어렵다** — 쓰는 곳이 여러 파일에 흩어져 있다.
#
# ⚠️ 그래서 **행동으로** 본다: 셋업 전 볼트를 통째로 지문 찍고, 셋업하고,
#    되돌린 뒤 **지문이 같은지** 본다. 어느 코드가 빠뜨렸는지 몰라도 잡힌다.
#
# ⚠️ 실제 사용자 볼트는 건드리지 않는다. 전부 임시 디렉터리다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

DT="$ROOT/bin/devtrail"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

V="$TMP/vault"; H="$TMP/home"; C="$TMP/config.json"
mkdir -p "$V/.obsidian" "$H"

# 사용자가 원래 갖고 있던 것들 — 셋업이 건드리면 안 되고, undo 도 지우면 안 된다.
mkdir -p "$V/내 폴더" "$V/.obsidian/snippets"
printf '# 내 노트\n' > "$V/내 폴더/노트.md"
printf '# 루트 노트\n' > "$V/기존 노트.md"
printf '{"theme":"obsidian"}\n' > "$V/.obsidian/appearance.json"
printf '/* 내 스타일 */\n' > "$V/.obsidian/snippets/mine.css"
# ⚠️ devtrail 이 쓰는 바로 그 이름. 이게 없으면 "덮어쓰기" 분기에 닿지 않아
#    백업 누락을 못 잡는다 (2026-08-24 변이에서 실제로 놓쳤다).
printf '/* 내가 먼저 만든 devtrail.css */\n' > "$V/.obsidian/snippets/devtrail.css"

# ⚠️ 볼트 전체의 지문. 경로 + 내용 해시 — 하나라도 다르면 드러난다.
fingerprint() {
  ( cd "$1" && find . -type f -print0 2>/dev/null \
      | LC_ALL=C sort -z \
      | xargs -0 shasum -a 256 2>/dev/null ) | shasum -a 256 | cut -d' ' -f1
}
listing() { ( cd "$1" && find . -type f 2>/dev/null | LC_ALL=C sort ); }

BEFORE=$(fingerprint "$V")
listing "$V" > "$TMP/before.txt"

t_start "전제 — 볼트에 사용자 파일이 있다"
t_eq "파일이 있다" "5" "$(wc -l < "$TMP/before.txt" | tr -d ' ')"

dt() { DEVTRAIL_HOME="$H/.devtrail" DEVTRAIL_CONFIG="$C" "$DT" "$@" < /dev/null; }

t_start "셋업을 적용한다"
OUT=$(dt setup quick --vault "$V" --lang ko --apply 2>&1)
t_eq "성공한다" "0" "$?"

# ⚠️ 템플릿·스니펫은 여기서 깔린다. 이 단계를 안 태우면 그 코드에 닿지
#    않아, 시험이 통과해도 아무것도 지키지 않는다.
OUT2=$(dt obsidian 2>&1)
t_eq "obsidian 적용도 성공한다" "0" "$?"

t_eq "볼트가 실제로 바뀌었다" "no" \
  "$([ "$(fingerprint "$V")" = "$BEFORE" ] && echo yes || echo no)"
# ⚠️ 정말로 템플릿·스니펫에 닿았는지 확인한다 — 안 닿았으면 아래가 헛돈다.
t_eq "전제 — 템플릿이 깔렸다" "yes" \
  "$([ "$(find "$V" -path '*템플릿*' -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" -gt 5 ] && echo yes || echo no)"
t_eq "전제 — 스니펫이 깔렸다" "yes" \
  "$([ "$(find "$V/.obsidian/snippets" -name 'devtrail.css' 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && echo yes || echo no)"

t_start "⚠️ 되돌리면 **원래대로** 돌아온다"
# ⚠️ 작업이 둘이다. 최신부터 거꾸로 되돌린다.
JOBS=$(ls -1 "$H/.devtrail/journal" 2>/dev/null | LC_ALL=C sort -r)
t_eq "되돌릴 작업이 둘이다" "2" "$(printf '%s\n' "$JOBS" | grep -c . | tr -d ' ')"
if [ -n "$JOBS" ]; then
  printf '%s\n' "$JOBS" | while IFS= read -r j; do
    [ -n "$j" ] && dt undo "$j" --apply >/dev/null 2>&1
  done
  listing "$V" > "$TMP/after.txt"

  # ⚠️ 남은 파일을 **이름으로** 보여준다. 지문만 비교하면 무엇이 남았는지
  #    알 수 없어 고칠 수가 없다.
  EXTRA=$(comm -13 "$TMP/before.txt" "$TMP/after.txt" | head -10)
  MISSING=$(comm -23 "$TMP/before.txt" "$TMP/after.txt" | head -10)

  t_eq "저널에 안 남은 파일이 없다 (undo 후 잔여)" "" "$EXTRA"
  t_eq "사용자 파일이 사라지지 않았다" "" "$MISSING"
  t_eq "볼트 지문이 원래와 같다" "$BEFORE" "$(fingerprint "$V")"
fi

t_start "⚠️ 사용자 것은 셋업이 덮어쓰지 않는다"
t_eq "내 노트가 그대로다" "# 내 노트" "$(cat "$V/내 폴더/노트.md" 2>/dev/null)"
t_eq "내 스니펫이 그대로다" "/* 내 스타일 */" "$(cat "$V/.obsidian/snippets/mine.css" 2>/dev/null)"
# ⚠️ 이름이 겹친 것도 되돌아와야 한다 — 셋업이 덮어썼다면 백업에서 복원된다.
t_eq "이름이 겹친 내 파일도 복원된다" "/* 내가 먼저 만든 devtrail.css */" \
  "$(cat "$V/.obsidian/snippets/devtrail.css" 2>/dev/null)"

t_start "⚠️ 없던 스니펫을 새로 만드는 경우도 되돌아온다"
# ⚠️ 위 시험은 devtrail.css 가 **이미 있는** 경우다 (덮어쓰기 분기).
#    없을 때(생성 분기)는 다른 코드가 돈다 — 그쪽도 저널에 남아야 한다.
#    한 픽스처로 두 분기를 다 태울 수 없어 단계를 나눈다.
rm -f "$V/.obsidian/snippets/devtrail.css"
B2=$(fingerprint "$V")
listing "$V" > "$TMP/b2.txt"
dt obsidian >/dev/null 2>&1
t_eq "전제 — 스니펫이 새로 생겼다" "yes" \
  "$([ -f "$V/.obsidian/snippets/devtrail.css" ] && echo yes || echo no)"
J2=$(ls -1 "$H/.devtrail/journal" 2>/dev/null | LC_ALL=C sort -r | head -1)
dt undo "$J2" --apply >/dev/null 2>&1
listing "$V" > "$TMP/a2.txt"
t_eq "새로 만든 것이 남지 않는다" "" "$(comm -13 "$TMP/b2.txt" "$TMP/a2.txt" | head -5)"
t_eq "지문이 원래대로다" "$B2" "$(fingerprint "$V")"

t_end
