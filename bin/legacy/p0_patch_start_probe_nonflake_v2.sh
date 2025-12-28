#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need ss; need egrep

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_probe_nonflake_v2_${TS}"
echo "[BACKUP] ${F}.bak_probe_nonflake_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_PROBE_NONFLAKE_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

needle = '== wait HTTP stable (/, /vsp5, /api/vsp/runs) =='
idx = s.find(needle)
if idx < 0:
    print("[ERR] cannot find probe banner:", needle)
    raise SystemExit(2)

# insert right after the banner line
eol = s.find("\n", idx)
if eol < 0:
    print("[ERR] malformed file (no newline after banner)")
    raise SystemExit(2)

inject = rf'''
# ==== {MARK} ====
# Commercial/P0: strict probe takes over and short-circuits legacy heuristic probe.
_vsp_http_code_head() {{ curl -sS -o /dev/null -w "%{{http_code}}" -I "$1" 2>/dev/null || echo 000; }}
_vsp_http_code_get()  {{ curl -sS -o /dev/null -w "%{{http_code}}" "$1"  2>/dev/null || echo 000; }}

_vsp_retry_code() {{
  local url="$1" expect="$2" tries="${{3:-10}}" sl="${{4:-0.20}}" mode="${{5:-get}}"
  local i code
  for i in $(seq 1 "$tries"); do
    if [ "$mode" = "head" ]; then code="$(_vsp_http_code_head "$url")"; else code="$(_vsp_http_code_get "$url")"; fi
    if echo "$code" | grep -Eq "$expect"; then
      echo "[OK] probe $url => $code (try $i/$tries)"
      return 0
    fi
    echo "[WARN] probe $url => $code (try $i/$tries) expect=/$expect/"
    sleep "$sl"
  done
  return 1
}}

_vsp_probe_json_ok() {{
  local url="$1" tries="${{2:-12}}" sl="${{3:-0.25}}"
  local i code body
  for i in $(seq 1 "$tries"); do
    code="$(_vsp_http_code_get "$url")"
    if [ "$code" = "200" ]; then
      body="$(curl -sS "$url" 2>/dev/null || true)"
      python3 - <<'PYC' "$body" >/dev/null 2>&1 || true
import json, sys
j=json.loads(sys.argv[1])
assert j.get("ok") is True
assert isinstance(j.get("items", []), list)
PYC
      if [ $? -eq 0 ]; then
        echo "[OK] probe $url => 200 + json.ok/items (try $i/$tries)"
        return 0
      fi
    fi
    echo "[WARN] probe $url => $code (try $i/$tries)"
    sleep "$sl"
  done
  return 1
}}

vsp_strict_probe_nonflake_p0() {{
  local BASE="${{VSP_UI_BASE:-http://127.0.0.1:8910}}"
  _vsp_retry_code "$BASE/" '^(200|302)$' 12 0.15 head || return 1
  _vsp_retry_code "$BASE/vsp5" '^200$'    12 0.20 get  || return 1
  _vsp_probe_json_ok "$BASE/api/vsp/runs?limit=1" 12 0.20 || return 1
  return 0
}}

if vsp_strict_probe_nonflake_p0; then
  echo "[OK] stable (strict probe, commercial/P0)"
  exit 0
else
  echo "[FAIL] not stable (strict probe, commercial/P0); tail logs:"
  tail -n 120 out_ci/ui_8910.boot.log 2>/dev/null || true
  exit 3
fi
# ==== /{MARK} ====

'''

s = s[:eol+1] + inject + s[eol+1:]
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

echo "== smoke =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -sS -I "$BASE/" | sed -n '1,12p' || true
curl -sS -I "$BASE/vsp5" | sed -n '1,12p' || true
curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 240; echo || true

echo "== boot log (last 80) =="
tail -n 80 out_ci/ui_8910.boot.log || true

echo "[DONE] non-flake probe V2 applied."
