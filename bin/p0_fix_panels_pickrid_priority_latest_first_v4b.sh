#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_commercial_panels_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_pickrid_v4b_${TS}"
echo "[BACKUP] ${JS}.bak_pickrid_v4b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, textwrap

p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_PANELS_PICKRID_PRIORITY_LATEST_FIRST_V4B"
if marker in s:
    print("[OK] v4b already applied")
    raise SystemExit(0)

# Replace the entire pickRidSmartPanels function (that we inserted in v4)
pat = re.compile(r'async function pickRidSmartPanels\s*\([^)]*\)\s*\{.*?\n\}\n', re.S)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find pickRidSmartPanels() to rewrite (v4 not installed?)")

new_fn = textwrap.dedent(r'''
/* VSP_P0_PANELS_PICKRID_PRIORITY_LATEST_FIRST_V4B */
async function pickRidSmartPanels(..._args){
  // 0) forced/global (if someone explicitly sets)
  try{
    const g = String((window.__VSP_SELECTED_RID||"")).trim();
    if (g) return g;
  }catch(e){}

  // 1) server truth FIRST (commercial: always follow newest run)
  try{
    const r = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
    if (r && r.ok){
      const j = await r.json();
      const rid = (j && j.ok && j.rid) ? String(j.rid).trim() : "";
      if (rid){
        try{ localStorage.setItem("vsp_selected_rid", rid); }catch(e){}
        try{ window.__VSP_SELECTED_RID = rid; }catch(e){}
        return rid;
      }
    }
  }catch(e){}

  // 2) fallback localStorage (only if server not available)
  try{
    const ls = (localStorage.getItem("vsp_selected_rid")||"").trim();
    if (ls) return ls;
  }catch(e){}

  // 3) last fallback: old global runs picker if present
  try{
    if (typeof pickRidFromRunsApi === "function"){
      const rr = await pickRidFromRunsApi(..._args);
      if (rr) return rr;
    }
  }catch(e){}
  return "";
}
''').lstrip("\n")

s2 = s[:m.start()] + new_fn + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] rewritten pickRidSmartPanels() to prefer /api/vsp/latest_rid first")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check $JS"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
