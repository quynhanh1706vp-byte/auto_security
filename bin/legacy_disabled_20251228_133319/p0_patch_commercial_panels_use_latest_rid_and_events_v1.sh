#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re, time

root = Path("static/js")
if not root.exists():
    raise SystemExit("[ERR] missing static/js")

# find candidate JS files by signature seen in your console: "P1PanelsEx"
cands = []
for p in root.glob("*.js"):
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "P1PanelsEx" in s or "commercial panels" in s.lower():
        cands.append((p, s))

if not cands:
    # fallback: any file name contains "commercial" and "panel"
    for p in root.glob("*.js"):
        if "commer" in p.name.lower() and "panel" in p.name.lower():
            s = p.read_text(encoding="utf-8", errors="replace")
            cands.append((p, s))

if not cands:
    raise SystemExit("[ERR] cannot locate commercial panels JS (no file contains P1PanelsEx)")

patched = 0
for p, s in cands:
    marker = "VSP_P0_PANELS_LATEST_RID_V1"
    if marker in s:
        print("[OK] already patched:", p)
        continue

    bak = p.with_name(p.name + f".bak_latestRid_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak.name)

    # inject resolver near top of IIFE if possible
    m = re.search(r'\(\s*\(\s*\)\s*=>\s*\{\s*\n', s) or re.search(r'\(\s*function\s*\(\s*\)\s*\{\s*\n', s)
    if not m:
        print("[WARN] cannot find IIFE start, skip:", p)
        continue

    inject_head = r'''
/* VSP_P0_PANELS_LATEST_RID_V1 */
let __vsp_p0_panels_force_rid = "";
const __vsp_p0_panels_ls_keys = ["vsp_selected_rid","vsp_rid","VSP_RID","vsp5_rid","vsp_gate_story_rid"];

async function __vsp_p0_panels_try_latest_rid(){
  try{
    const r = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
    if (!r.ok) return "";
    const j = await r.json();
    if (j && j.ok && j.rid) return String(j.rid);
  }catch(e){}
  return "";
}
function __vsp_p0_panels_try_ls(){
  try{
    for (const k of __vsp_p0_panels_ls_keys){
      const v = (localStorage.getItem(k)||"").trim();
      if (v) return v;
    }
  }catch(e){}
  return "";
}
async function pickRidSmart(){
  if (__vsp_p0_panels_force_rid) return __vsp_p0_panels_force_rid;
  const ls = __vsp_p0_panels_try_ls();
  if (ls) return ls;
  const lr = await __vsp_p0_panels_try_latest_rid();
  if (lr) return lr;
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

    # replace RID selection calls: await pickRidFromRunsApi() -> await pickRidSmart()
    s, n = re.subn(r'await\s+pickRidFromRunsApi\s*\(\s*\)', 'await pickRidSmart()', s, count=10)
    print(f"[OK] {p.name}: replaced pickRidFromRunsApi() calls = {n}")

    # add event hooks near end of file
    tail_idx = s.rfind("})();")
    if tail_idx == -1:
        tail_idx = len(s)

    inject_tail = r'''
try{
  window.__vsp_panels_set_rid = (rid)=> {
    try{
      const r = String(rid||"").trim();
      if (!r) return;
      __vsp_p0_panels_force_rid = r;
      try{ localStorage.setItem("vsp_selected_rid", r); }catch(e){}
      try{ window.__VSP_SELECTED_RID = r; }catch(e){}
      try{ if (typeof main === "function") main(); }catch(e){}
    }catch(e){}
  };
  window.addEventListener("vsp:rid", (e)=> {
    try{
      const r = String(e && e.detail && e.detail.rid ? e.detail.rid : "").trim();
      if (!r) return;
      if (r === __vsp_p0_panels_force_rid) return;
      __vsp_p0_panels_force_rid = r;
      try{ if (typeof main === "function") main(); }catch(e){}
    }catch(e){}
  });
}catch(e){}
'''
    s = s[:tail_idx] + inject_tail + "\n" + s[tail_idx:]

    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", p.name)
    patched += 1

print("[DONE] patched_files=", patched)
PY

# node checks for all candidate files (best effort)
if command -v node >/dev/null 2>&1; then
  for f in static/js/*.js; do
    grep -q "VSP_P0_PANELS_LATEST_RID_V1" "$f" 2>/dev/null || continue
    node --check "$f" && echo "[OK] node --check $f"
  done
fi

echo "[DONE] Now hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
