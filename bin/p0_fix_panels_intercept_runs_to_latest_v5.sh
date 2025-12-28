#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_commercial_panels_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runs_intercept_v5_${TS}"
echo "[BACKUP] ${JS}.bak_runs_intercept_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_PANELS_RUNS_TO_LATEST_INTERCEPT_V5"
if MARK in s:
    print("[OK] v5 already applied")
    raise SystemExit(0)

# find async fetchJSON(...) {  ... } and inject at start of body
patterns = [
  r'async\s+function\s+fetchJSON\s*\(\s*url[^)]*\)\s*\{',
  r'const\s+fetchJSON\s*=\s*async\s*\(\s*url[^)]*\)\s*=>\s*\{',
  r'let\s+fetchJSON\s*=\s*async\s*\(\s*url[^)]*\)\s*=>\s*\{',
]

m = None
for pat in patterns:
    m = re.search(pat, s)
    if m: break
if not m:
    print("[ERR] cannot locate async fetchJSON(url..) to patch")
    sys.exit(2)

ins = m.end()
indent = re.match(r'[ \t]*', s[ins:]).group(0)

inject = r'''
/* VSP_P0_PANELS_RUNS_TO_LATEST_INTERCEPT_V5 */
try{
  const u = String(url||"");
  // Panels legacy picker hits /api/vsp/runs?limit=1 -> force server truth
  if (u.includes("/api/vsp/runs") && u.includes("limit=1")){
    try{
      const r = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
      if (r && r.ok){
        const j = await r.json();
        const rid = (j && j.ok && j.rid) ? String(j.rid).trim() : "";
        if (rid){
          // shape compatible with runs API callers
          return { ok:true, limit:1, runs:[{ rid, run_id:rid, id:rid, path:j.path, mtime:j.mtime, mtime_iso:j.mtime_iso }] };
        }
      }
    }catch(e){}
  }
}catch(e){}
'''.strip("\n")

s2 = s[:ins] + "\n" + indent + inject.replace("\n", "\n"+indent) + "\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected runs->latest intercept into fetchJSON()")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check $JS"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
