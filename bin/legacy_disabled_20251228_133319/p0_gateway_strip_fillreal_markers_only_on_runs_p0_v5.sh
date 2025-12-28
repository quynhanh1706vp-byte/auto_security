#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_strip_markers_runs_${TS}"
echo "[BACKUP] ${F}.bak_strip_markers_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_STRIP_FILLREAL_MARKERS_ON_RUNS_V5"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Locate the middleware function block
m = re.search(r'(?s)\ndef\s+_vsp_mw_strip_fillreal_on_runs\s*\(.*?\)\s*:\s*(?P<body>.*?)\n\s*return\s+_mw\s*\n', s)
if not m:
    print("[ERR] cannot find _vsp_mw_strip_fillreal_on_runs() block")
    raise SystemExit(2)

body = m.group("body")

# Determine whether the function uses `re` or `_re` for regex ops
uses__re = "_re.sub" in body or "import re as _re" in body
rx = "_re" if uses__re else "re"

# Find a good insertion point: right after html = body.decode(...)
decode_pat = re.compile(r'(?m)^(?P<indent>\s*)html\s*=\s*body\.decode\(\s*[\'"]utf-8[\'"]\s*,\s*[\'"]replace[\'"]\s*\)\s*$')
dm = decode_pat.search(body)
if not dm:
    # fallback: any decode line
    decode_pat2 = re.compile(r'(?m)^(?P<indent>\s*).*body\.decode\(.+\)\s*$')
    dm = decode_pat2.search(body)
if not dm:
    print("[ERR] cannot find decode() line inside middleware")
    raise SystemExit(3)

indent = dm.group("indent")
inject = (
    f"{indent}# strip gateway marker comments too (runs-only)\n"
    f"{indent}html = {rx}.sub(r\"\\s*<!--\\s*VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\\s*-->\\s*\", \"\", html, flags={rx}.I)\n"
    f"{indent}html = {rx}.sub(r\"\\s*<!--\\s*/VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\\s*-->\\s*\", \"\", html, flags={rx}.I)\n"
    f"{indent}# {MARK}\n"
)

# Prevent double insert
if "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" in body and MARK in body:
    print("[OK] markers already stripped in MW")
    raise SystemExit(0)

# Insert right after the decode line
insert_pos = dm.end()
body2 = body[:insert_pos] + "\n" + inject + body[insert_pos:]

# Rebuild file
s2 = s[:m.start("body")] + body2 + s[m.end("body"):]
p.write_text(s2, encoding="utf-8")
print("[OK] injected marker-strip into MW (robust)")
PY

rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify /runs clean (no marker, no script) =="
curl -sS http://127.0.0.1:8910/runs -o /tmp/runs.html
grep -n "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" /tmp/runs.html && echo "[ERR] marker still present" || echo "[OK] no marker"
grep -n "vsp_fill_real_data_5tabs_p1_v1\\.js" /tmp/runs.html && echo "[ERR] script still present" || echo "[OK] no script"
