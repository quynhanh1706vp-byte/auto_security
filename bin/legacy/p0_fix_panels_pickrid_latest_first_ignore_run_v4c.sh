#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_commercial_panels_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_pickrid_v4c_${TS}"
echo "[BACKUP] ${JS}.bak_pickrid_v4c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, sys

p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_PANELS_PICKRID_LATEST_FIRST_IGNORE_RUN_V4C"
if marker in s:
    print("[OK] v4c already applied")
    raise SystemExit(0)

pat = re.compile(r'async function pickRidSmartPanels\s*\([^)]*\)\s*\{.*?\n\}\n', re.S)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find pickRidSmartPanels() to rewrite")

new_fn = textwrap.dedent(r'''
/* VSP_P0_PANELS_PICKRID_LATEST_FIRST_IGNORE_RUN_V4C */
async function pickRidSmartPanels(..._args){
  const isBad = (r)=> {
    try{
      const x = String(r||"").trim();
      if (!x) return True; // empty = bad
      // commercial: RUN_* is legacy local RID, ignore if possible
      if (x.startsWith("RUN_")) return True;
      return False;
    }catch(e){ return True; }
  };

  // 1) server truth FIRST
  try{
    const resp = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
    if (resp && resp.ok){
      const j = await resp.json();
      const rid = (j && j.ok && j.rid) ? String(j.rid).trim() : "";
      if (rid && !rid.startsWith("RUN_")){
        try{ localStorage.setItem("vsp_selected_rid", rid); }catch(e){}
        try{ window.__VSP_SELECTED_RID = rid; }catch(e){}
        return rid;
      }
    }
  }catch(e){}

  // 2) fallback: prefer non-RUN global/localStorage
  try{
    const g = String((window.__VSP_SELECTED_RID||"")).trim();
    if (g && !g.startsWith("RUN_")) return g;
  }catch(e){}
  try{
    const ls = (localStorage.getItem("vsp_selected_rid")||"").trim();
    if (ls && !ls.startsWith("RUN_")) return ls;
  }catch(e){}

  // 3) last fallback: legacy runs picker if present
  try{
    if (typeof pickRidFromRunsApi === "function"){
      const rr = await pickRidFromRunsApi(..._args);
      const rid = String(rr||"").trim();
      if (rid){
        try{ localStorage.setItem("vsp_selected_rid", rid); }catch(e){}
        try{ window.__VSP_SELECTED_RID = rid; }catch(e){}
        return rid;
      }
    }
  }catch(e){}
  return "";
}
''').lstrip("\n")

s2 = s[:m.start()] + new_fn + s[m.end():]

# also: if global/localStorage currently holds RUN_, clear it once at load (silent)
if "VSP_P0_PANELS_CLEAR_RUN_SELECTED_V1" not in s2:
    ins = "/* VSP_P0_PANELS_CLEAR_RUN_SELECTED_V1 */\ntry{\n  const g=String((window.__VSP_SELECTED_RID||\"\"));\n  if (g.startsWith(\"RUN_\")) window.__VSP_SELECTED_RID=\"\";\n}catch(e){}\ntry{\n  const ls=(localStorage.getItem(\"vsp_selected_rid\")||\"\");\n  if (ls.startsWith(\"RUN_\")) localStorage.removeItem(\"vsp_selected_rid\");\n}catch(e){}\n"
    # inject right after the rewritten function
    s2 = s2.replace(new_fn, new_fn + "\n" + ins, 1)

p.write_text(s2, encoding="utf-8")
print("[OK] rewritten pickRidSmartPanels(): latest first + ignore RUN_* + clear stale RUN_*")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check $JS"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
