#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need ss; need grep; need egrep

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_probe_nonflake_${TS}"
echo "[BACKUP] ${F}.bak_probe_nonflake_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_PROBE_NONFLAKE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# soften legacy message if present (optional, cosmetic)
s = s.replace("treating as OK", "treating as FAIL (strict probe active)")

inject = r'''
# ==== {MARK} ====
# Commercial/P0: make probes deterministic:
# - accept / as 200 or 302
# - retry short for /vsp5 and /api/vsp/runs?limit=1
# - fail hard if still not stable (no more "probe flaked but OK")

_vsp_http_code_head() {{
  curl -sS -o /dev/null -w "%{{http_code}}" -I "$1" 2>/dev/null || echo 000
}}

_vsp_http_code_get() {{
  curl -sS -o /dev/null -w "%{{http_code}}" "$1" 2>/dev/null || echo 000
}}

_vsp_retry_code() {{
  # usage: _vsp_retry_code <url> <expect_regex> <tries> <sleep_sec> <head|get>
  local url="$1" expect="$2" tries="${{3:-8}}" sl="${{4:-0.25}}" mode="${{5:-get}}"
  local i code
  for i in $(seq 1 "$tries"); do
    if [ "$mode" = "head" ]; then
      code="$(_vsp_http_code_head "$url")"
    else
      code="$(_vsp_http_code_get "$url")"
    fi
    if echo "$code" | grep -Eq "$expect"; then
      echo "[OK] probe $url => $code (try $i/$tries)"
      return 0
    fi
    echo "[WARN] probe $url => $code (try $i/$tries) expect=/$expect/"
    sleep "$sl"
  done
  echo "[FAIL] probe $url did not reach expect=/$expect/ after $tries tries"
  return 1
}}

_vsp_probe_json_ok() {{
  # usage: _vsp_probe_json_ok <url> <tries> <sleep_sec>
  local url="$1" tries="${{2:-8}}" sl="${{3:-0.25}}"
  local i code body
  for i in $(seq 1 "$tries"); do
    code="$(_vsp_http_code_get "$url")"
    if [ "$code" = "200" ]; then
      body="$(curl -sS "$url" 2>/dev/null || true)"
      python3 - <<'PYC' "$body" >/dev/null 2>&1 || {{
import json, sys
raw = sys.argv[1]
j = json.loads(raw)
assert j.get("ok") is True
assert isinstance(j.get("items", []), list)
PYC
        echo "[OK] probe $url => 200 + json.ok/items (try $i/$tries)"
        return 0
      }}
      echo "[WARN] probe $url => 200 but json invalid (try $i/$tries)"
    else
      echo "[WARN] probe $url => $code (try $i/$tries) expect=200"
    fi
    sleep "$sl"
  done
  echo "[FAIL] probe $url did not reach (200 + valid json) after $tries tries"
  return 1
}}

vsp_strict_probe_nonflake_p0() {{
  local BASE="${{VSP_UI_BASE:-http://127.0.0.1:8910}}"
  local ok=1

  # 1) / : accept 200 or 302
  if ! _vsp_retry_code "$BASE/" '^(200|302)$' 10 0.20 head; then ok=0; fi

  # 2) If redirected, try ensure /vsp5 becomes ready
  if ! _vsp_retry_code "$BASE/vsp5" '^200$' 12 0.25 get; then ok=0; fi

  # 3) API runs contract minimal: http 200 + json ok/items
  if ! _vsp_probe_json_ok "$BASE/api/vsp/runs?limit=1" 12 0.25; then ok=0; fi

  if [ "$ok" -ne 1 ]; then
    echo "[FAIL] strict probe: NOT STABLE (commercial/P0)"
    return 1
  fi
  echo "[OK] strict probe: STABLE (commercial/P0)"
  return 0
}}
# ==== /{MARK} ====
'''.format(MARK=MARK)

# Insert before last "exit 0" if possible; else append.
idx = s.rfind("\nexit 0")
if idx != -1:
    s = s[:idx] + "\n" + inject + "\n\n# run strict probe\nif ! vsp_strict_probe_nonflake_p0; then exit 3; fi\n\n" + s[idx:]
else:
    s = s.rstrip() + "\n\n" + inject + "\n\n# run strict probe\nif ! vsp_strict_probe_nonflake_p0; then exit 3; fi\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

bash -n "$F"
echo "[OK] bash -n OK: $F"

echo "== restart clean =="
: > nohup.out || true
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1.2

echo "== ss (8910/8000) =="
ss -ltnp | egrep '(:8910|:8000)' || true

echo "== smoke headers =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -sS -I "$BASE/" | sed -n '1,12p' || true
curl -sS -I "$BASE/vsp5" | sed -n '1,12p' || true
curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 240; echo || true

echo "== boot log (last 120) =="
tail -n 120 out_ci/ui_8910.boot.log || true

echo "[DONE] probe non-flake patch applied."
