#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK="${F}.bak_fix_overall_runsv3_v6_${TS}"
cp -f "$F" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_FIX_OVERALL_RUNS_V3_INLINE_PAYLOAD_V6"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

lines = s.splitlines(True)

fn = "vsp_apiui_runs_v3"
# locate def
def_line = None
for i, ln in enumerate(lines):
    if re.match(rf'^\s*def\s+{re.escape(fn)}\s*\(', ln):
        def_line = i
        break
if def_line is None:
    print("[ERR] cannot find def", fn)
    raise SystemExit(2)

def_indent = len(lines[def_line]) - len(lines[def_line].lstrip(" "))
end = len(lines)
for k in range(def_line+1, len(lines)):
    t = lines[k].strip()
    if not t:
        continue
    ind = len(lines[k]) - len(lines[k].lstrip(" "))
    if ind <= def_indent and (t.startswith("@") or t.startswith("def ") or t.startswith("class ") or re.match(r'^\w', t)):
        end = k
        break

body = lines[def_line:end]

# find the line: return __vsp__json({
start_i = None
indent = ""
for i, ln in enumerate(body):
    m = re.match(r'^(\s*)return\s+__vsp__json\s*\(\s*\{\s*$', ln)
    if m:
        indent = m.group(1)
        start_i = i
        break

if start_i is None:
    # fallback: allow spaces: return __vsp__json({
    for i, ln in enumerate(body):
        if re.match(r'^(\s*)return\s+__vsp__json\s*\(\s*\{\s*$', ln):
            indent = re.match(r'^(\s*)', ln).group(1)
            start_i = i
            break

if start_i is None:
    print("[ERR] cannot find line 'return __vsp__json({' inside", fn)
    raise SystemExit(3)

# find end of block (the matching "})" that closes __vsp__json({ ... })
# We'll bracket-balance from the "{"
def bal(txt: str):
    return (txt.count("{")-txt.count("}"),
            txt.count("(")-txt.count(")"),
            txt.count("[")-txt.count("]"))

bc, bp, bb = bal("{")  # we are inside dict
end_i = start_i
j = start_i + 1
while j < len(body):
    bc2, bp2, bb2 = bal(body[j])
    bc += bc2; bp += bp2; bb += bb2
    # we expect to hit a line that contains "})" at the end (or with spaces)
    if bc <= 0 and re.search(r'\}\s*\)\s*$', body[j]):
        end_i = j
        break
    j += 1

if end_i == start_i:
    print("[ERR] cannot find closing '})' for __vsp__json({ ... }) block")
    raise SystemExit(4)

print("[OK] found return block span:", start_i, "->", end_i)

# rewrite:
#   return __vsp__json({   ->   __vsp__payload = {
body[start_i] = re.sub(r'^(\s*)return\s+__vsp__json\s*\(\s*\{\s*$',
                       r'\1__vsp__payload = {',
                       body[start_i], count=1)

# last line: replace "})" -> "}"
body[end_i] = re.sub(r'\}\s*\)\s*$', r'}', body[end_i], count=1)

# inject inference + return after end_i
hook = (
f"{indent}# {MARK}\n"
f"{indent}try:\n"
f"{indent}    __items = __vsp__payload.get('items')\n"
f"{indent}    if isinstance(__items, list):\n"
f"{indent}        for __it in __items:\n"
f"{indent}            if not isinstance(__it, dict):\n"
f"{indent}                continue\n"
f"{indent}            __has_gate = bool(__it.get('has_gate'))\n"
f"{indent}            __overall = str(__it.get('overall') or '').strip().upper()\n"
f"{indent}            __counts  = __it.get('counts') or {{}}\n"
f"{indent}            __total   = __it.get('findings_total') or __it.get('total') or 0\n"
f"{indent}            def _i(v, d=0):\n"
f"{indent}                try: return int(v) if v is not None else d\n"
f"{indent}                except Exception: return d\n"
f"{indent}            __c = _i(__counts.get('CRITICAL') or __counts.get('critical'), 0)\n"
f"{indent}            __h = _i(__counts.get('HIGH') or __counts.get('high'), 0)\n"
f"{indent}            __m = _i(__counts.get('MEDIUM') or __counts.get('medium'), 0)\n"
f"{indent}            __l = _i(__counts.get('LOW') or __counts.get('low'), 0)\n"
f"{indent}            __inf = _i(__counts.get('INFO') or __counts.get('info'), 0)\n"
f"{indent}            __t = _i(__counts.get('TRACE') or __counts.get('trace'), 0)\n"
f"{indent}            __tot = _i(__total, 0)\n"
f"{indent}            if (__c > 0) or (__h > 0):\n"
f"{indent}                __inferred = 'RED'\n"
f"{indent}            elif (__m > 0):\n"
f"{indent}                __inferred = 'AMBER'\n"
f"{indent}            elif (__tot > 0) or ((__l+__inf+__t) > 0):\n"
f"{indent}                __inferred = 'GREEN'\n"
f"{indent}            else:\n"
f"{indent}                __inferred = 'GREEN'\n"
f"{indent}            __it['overall_inferred'] = __inferred\n"
f"{indent}            if __has_gate and __overall and (__overall != 'UNKNOWN'):\n"
f"{indent}                __it['overall_source'] = 'gate'\n"
f"{indent}            else:\n"
f"{indent}                if (not __overall) or (__overall == 'UNKNOWN'):\n"
f"{indent}                    __it['overall'] = __inferred\n"
f"{indent}                __it['overall_source'] = 'inferred_counts'\n"
f"{indent}except Exception:\n"
f"{indent}    pass\n"
f"{indent}return __vsp__json(__vsp__payload)\n"
)

body.insert(end_i + 1, hook)

lines[def_line:end] = body
p.write_text("".join(lines), encoding="utf-8")
print("[OK] patched", fn, "inline payload + overall inference")
PY

# transactional compile: fail => restore backup and exit
if ! python3 -m py_compile wsgi_vsp_ui_gateway.py; then
  echo "[ERR] py_compile failed -> restore $BAK"
  cp -f "$BAK" wsgi_vsp_ui_gateway.py
  python3 -m py_compile wsgi_vsp_ui_gateway.py || true
  exit 3
fi
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify =="
ss -ltnp | egrep '(:8910)' || true

RAW="$(curl -sS "$BASE/api/ui/runs_v3?limit=3" || true)"
python3 - <<PY
import json,sys
raw = """$RAW"""
if not raw.strip():
    print("[ERR] empty response (service not up?)")
    sys.exit(0)
d=json.loads(raw)
for it in (d.get("items") or [])[:3]:
    print(it.get("rid"), it.get("has_gate"), it.get("overall"), it.get("overall_source"), it.get("overall_inferred"))
PY
