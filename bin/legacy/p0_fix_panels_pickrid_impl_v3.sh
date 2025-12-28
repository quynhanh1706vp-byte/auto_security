#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_commercial_panels_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_pickrid_impl_v3_${TS}"
echo "[BACKUP] ${JS}.bak_pickrid_impl_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_PANELS_PICKRID_IMPL_V3"
if marker in s:
    print("[OK] impl v3 already present")
    raise SystemExit(0)

inject_async = r'''
/* VSP_P0_PANELS_PICKRID_IMPL_V3 */
try{
  // 1) prefer forced/global or localStorage (rid_autofix sets these)
  const _ls = (()=>{ try{return (localStorage.getItem("vsp_selected_rid")||"").trim();}catch(e){return "";} })();
  const _g  = String((window.__VSP_SELECTED_RID||"")).trim();
  if (_g) return _g;
  if (_ls) return _ls;

  // 2) prefer server truth
  try{
    const r = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
    if (r && r.ok){
      const j = await r.json();
      const rid = (j && j.ok && j.rid) ? String(j.rid) : "";
      if (rid){
        try{ localStorage.setItem("vsp_selected_rid", rid); }catch(e){}
        try{ window.__VSP_SELECTED_RID = rid; }catch(e){}
        return rid;
      }
    }
  }catch(e){}
}catch(e){}
'''

inject_sync = r'''
/* VSP_P0_PANELS_PICKRID_IMPL_V3 */
try{
  const _ls = (()=>{ try{return (localStorage.getItem("vsp_selected_rid")||"").trim();}catch(e){return "";} })();
  const _g  = String((window.__VSP_SELECTED_RID||"")).trim();
  if (_g) return _g;
  if (_ls) return _ls;
}catch(e){}
'''

def patch_first(pattern, is_async: bool):
    global s
    m = re.search(pattern, s, flags=re.M)
    if not m:
        return False
    # find insertion point right after "{"
    ins = m.end()
    # keep indentation: take whitespace before body (after newline)
    indent = re.match(r'[ \t]*', s[ins:]).group(0)
    add = (inject_async if is_async else inject_sync).strip("\n")
    s = s[:ins] + "\n" + indent + add.replace("\n", "\n"+indent) + "\n" + s[ins:]
    return True

# Try async function styles first
ok = (
    patch_first(r'async\s+function\s+pickRidFromRunsApi\s*\([^)]*\)\s*\{', True) or
    patch_first(r'const\s+pickRidFromRunsApi\s*=\s*async\s*\([^)]*\)\s*=>\s*\{', True) or
    patch_first(r'let\s+pickRidFromRunsApi\s*=\s*async\s*\([^)]*\)\s*=>\s*\{', True) or
    patch_first(r'var\s+pickRidFromRunsApi\s*=\s*async\s*\([^)]*\)\s*=>\s*\{', True)
)

# Fallback: non-async function (no await)
if not ok:
    ok = (
        patch_first(r'function\s+pickRidFromRunsApi\s*\([^)]*\)\s*\{', False) or
        patch_first(r'const\s+pickRidFromRunsApi\s*=\s*\([^)]*\)\s*=>\s*\{', False)
    )

if not ok:
    print("[ERR] cannot locate pickRidFromRunsApi definition to patch")
    sys.exit(2)

p.write_text(s, encoding="utf-8")
print("[OK] injected preferred RID logic into pickRidFromRunsApi()")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check $JS"
fi

echo "[DONE] Now hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
