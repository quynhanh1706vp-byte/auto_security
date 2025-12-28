#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp; need grep
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }
command -v systemctl >/dev/null 2>&1 || true

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_fixsyntax_endpoints_${TS}"
echo "[BACKUP] ${JS}.bak_fixsyntax_endpoints_${TS}"

echo "== [0] node --check BEFORE =="
node --check "$JS" 2>&1 | head -n 40 || true

python3 - "$JS" <<'PY'
from pathlib import Path
import re, sys

js = Path(sys.argv[1])
s = js.read_text(encoding="utf-8", errors="replace")
orig = s

# --- A) Kill hard syntax errors: "const = ..."  -> "const rid = ..."
# Keep indentation, keep RHS.
s = re.sub(
    r'(?m)^([ \t]*)const[ \t]*=[ \t]*(.+)$',
    r'\1const rid = \2',
    s
)

# --- B) Fix the common bad line: "rid = (window.__vspGetRid ...)" -> const rid / urlRid + fallback
# Replace any single line that contains __vspGetRid / URLSearchParams rid getter.
def _rid_block(indent: str) -> str:
    return (
        f"{indent}const urlRid = (window.__vspGetRid ? window.__vspGetRid() : ((new URLSearchParams(location.search).get(\"rid\")||\"\").trim()));\n"
        f"{indent}const rid = ((urlRid || (latest && (latest.rid || latest.run_id || latest.id)) || \"\").toString().trim());"
    )

# 1) If there's already a line assigning rid using __vspGetRid, replace it by 2-line robust block.
pat1 = re.compile(r'(?m)^([ \t]*)rid[ \t]*=[ \t]*\(\s*window\.__vspGetRid.*\)\s*;\s*$')
if pat1.search(s):
    s = pat1.sub(lambda m: _rid_block(m.group(1)), s)
else:
    # 2) If "const rid = ..." exists but is "const rid = (window.__vspGetRid ...)", normalize to urlRid+fallback
    pat2 = re.compile(r'(?m)^([ \t]*)const[ \t]+rid[ \t]*=[ \t]*\(\s*window\.__vspGetRid.*\)\s*;\s*$')
    if pat2.search(s):
        s = pat2.sub(lambda m: _rid_block(m.group(1)), s)

# --- C) Endpoint normalization: run_file -> run_file_allow ; name= -> path=
s = s.replace("/api/vsp/run_file", "/api/vsp/run_file_allow")
s = s.replace("name=", "path=")

# --- D) Patch api.runFile builder if present: ensure it uses run_file_allow + path=
# Handles: runFile: (rid, name)=> ... or runFile:(rid,path)=>...
s = re.sub(
    r'(?m)(runFile\s*:\s*\(\s*rid\s*,\s*)(name|path)(\s*\)\s*=>\s*)(.+)$',
    lambda m: (
        m.group(1) + "path" + m.group(3) +
        'BASE + "/api/vsp/run_file_allow?rid=" + enc(rid) + "&path=" + enc(path) + "&limit=200",'
    ),
    s
)

# --- E) "Open" button: do NOT call run_file_allow with folder "reports/" (often invalid / noisy).
# Replace href: api.runFile(rid,"reports/")  -> href: (BASE+"/runs?rid="+enc(rid))
s = re.sub(
    r'href\s*:\s*api\.runFile\(\s*rid\s*,\s*["\']reports/["\']\s*\)',
    r'href: (BASE + "/runs?rid=" + enc(rid))',
    s
)

if s != orig:
    js.write_text(s, encoding="utf-8")
else:
    print("[WARN] no changes applied (patterns not found)")

PY

echo "== [1] node --check AFTER =="
node --check "$JS" 2>&1 | head -n 60

echo "== [2] Quick grep for bad patterns (should be empty) =="
grep -nE '^\s*const\s*=\s*|^\s*rid\s*=\s*\(window\.__vspGetRid' "$JS" || true

echo "== [3] Restart service (best-effort) =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
fi

echo "[OK] done."
