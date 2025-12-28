#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_latestRid_${TS}"
echo "[BACKUP] ${JS}.bak_latestRid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_GATE_STORY_LATEST_RID_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Insert smart RID resolver just after IIFE start
m = re.search(r'\(\s*\(\s*\)\s*=>\s*\{\s*\n', s)
if not m:
    # fallback for "(function(){"
    m = re.search(r'\(\s*function\s*\(\s*\)\s*\{\s*\n', s)
if not m:
    raise SystemExit("[ERR] cannot find IIFE start to inject")

inject_head = r'''
/* VSP_P0_GATE_STORY_LATEST_RID_V1 */
let __vsp_p0_gate_story_force_rid = "";
const __vsp_p0_gate_story_ls_keys = [
  "vsp_selected_rid","vsp_rid","VSP_RID","vsp5_rid","vsp_gate_story_rid"
];

async function __vsp_p0_gate_story_try_latest_rid(){
  try{
    const r = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
    if (!r.ok) return "";
    const j = await r.json();
    if (j && j.ok && j.rid) return String(j.rid);
  }catch(e){}
  return "";
}

function __vsp_p0_gate_story_try_ls(){
  try{
    for (const k of __vsp_p0_gate_story_ls_keys){
      const v = (localStorage.getItem(k)||"").trim();
      if (v) return v;
    }
  }catch(e){}
  return "";
}

async function pickRidSmart(){
  // 0) forced rid (from rid_autofix event)
  if (__vsp_p0_gate_story_force_rid) return __vsp_p0_gate_story_force_rid;

  // 1) localStorage (user selection)
  const ls = __vsp_p0_gate_story_try_ls();
  if (ls) return ls;

  // 2) server latest rid (commercial truth)
  const lr = await __vsp_p0_gate_story_try_latest_rid();
  if (lr) return lr;

  // 3) fallback to existing logic
  try{
    if (typeof pickRidFromRunsApi === "function"){
      const rr = await pickRidFromRunsApi();
      if (rr) return rr;
    }
  }catch(e){}
  return "";
}
'''
s = s[:m.end()] + inject_head + s[m.end():]

# 2) Replace main RID selection call: prefer pickRidSmart()
# Replace occurrences of pickRidFromRunsApi() inside main flow.
# We'll replace the first "await pickRidFromRunsApi(" or "await pickRidFromRunsApi()" with pickRidSmart.
s2, n = re.subn(r'await\s+pickRidFromRunsApi\s*\(\s*\)', 'await pickRidSmart()', s, count=5)
s = s2
print(f"[OK] replaced pickRidFromRunsApi() calls: {n}")

# 3) Hook events + expose setter near the end of IIFE (before the last '})();')
tail_idx = s.rfind("})();")
if tail_idx == -1:
    # fallback "})();" not found => try "})();\n" variants
    m2 = re.search(r'\}\)\s*;\s*$', s)
    if not m2:
        raise SystemExit("[ERR] cannot find IIFE end to inject tail hook")
    tail_idx = m2.start()

inject_tail = r'''
try{
  // Allow rid_autofix to drive GateStory without reload
  window.__vsp_gate_story_set_rid = (rid)=> {
    try{
      const r = String(rid||"").trim();
      if (!r) return;
      __vsp_p0_gate_story_force_rid = r;
      try{ localStorage.setItem("vsp_selected_rid", r); }catch(e){}
      try{ window.__VSP_SELECTED_RID = r; }catch(e){}
      try{ main(); }catch(e){}
    }catch(e){}
  };

  window.__vsp_gate_story_refresh = ()=> { try{ main(); }catch(e){} };

  window.addEventListener("vsp:rid", (e)=> {
    try{
      const r = String(e && e.detail && e.detail.rid ? e.detail.rid : "").trim();
      if (!r) return;
      if (r === __vsp_p0_gate_story_force_rid) return;
      __vsp_p0_gate_story_force_rid = r;
      try{ main(); }catch(e){}
    }catch(e){}
  });
}catch(e){}
'''
s = s[:tail_idx] + inject_tail + "\n" + s[tail_idx:]

p.write_text(s, encoding="utf-8")
print("[OK] injected GateStory latest_rid + event hooks")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check gate_story OK"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
