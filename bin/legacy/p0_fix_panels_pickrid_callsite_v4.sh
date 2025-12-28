#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_commercial_panels_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_pickrid_callsite_v4_${TS}"
echo "[BACKUP] ${JS}.bak_pickrid_callsite_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_PANELS_PICKRID_CALLSITE_V4"
if MARK in s:
    print("[OK] v4 already applied")
    raise SystemExit(0)

# inject helper near top of IIFE
m = re.search(r'\(\s*\(\s*\)\s*=>\s*\{\s*\n', s) or re.search(r'\(\s*function\s*\(\s*\)\s*\{\s*\n', s)
if not m:
    raise SystemExit("[ERR] cannot find IIFE start in panels JS")

inject = r'''
/* VSP_P0_PANELS_PICKRID_CALLSITE_V4 */
async function pickRidSmartPanels(..._args){
  try{
    const g = String((window.__VSP_SELECTED_RID||"")).trim();
    if (g) return g;
  }catch(e){}
  try{
    const ls = (localStorage.getItem("vsp_selected_rid")||"").trim();
    if (ls) return ls;
  }catch(e){}

  // server truth
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

  // final fallback: if old global exists and is callable
  try{
    if (typeof pickRidFromRunsApi === "function"){
      const rr = await pickRidFromRunsApi(..._args);
      if (rr) return rr;
    }
  }catch(e){}
  return "";
}

// react to rid_autofix events
try{
  window.addEventListener("vsp:rid", (e)=> {
    try{
      const rid = String(e && e.detail && e.detail.rid ? e.detail.rid : "").trim();
      if (!rid) return;
      window.__VSP_SELECTED_RID = rid;
      try{ localStorage.setItem("vsp_selected_rid", rid); }catch(_){}
      try{ if (typeof main === "function") main(); }catch(_){}
    }catch(_){}
  });
}catch(_){}
'''
s = s[:m.end()] + inject + s[m.end():]

# Replace call sites: pickRidFromRunsApi(  -> pickRidSmartPanels(
# Only replace the call form (identifier followed by '(') to avoid touching logs/strings
s2, n = re.subn(r'\bpickRidFromRunsApi\s*\(', 'pickRidSmartPanels(', s)
if n == 0:
    print("[WARN] no callsite 'pickRidFromRunsApi(' found to replace (maybe already removed?)")
else:
    print("[OK] replaced callsites:", n)
s = s2

p.write_text(s, encoding="utf-8")
print("[OK] wrote v4 pickRidSmartPanels + callsite rewrites")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check $JS"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
