#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_v7ridlatest_${TS}"
echo "[BACKUP] ${JS}.bak_v7ridlatest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_DASH_MINICHARTS_V7_ONLY_SAFE_V1" not in s:
    raise SystemExit("[ERR] V7 marker not found. Apply v7_only script first.")

# Replace getRID() in V7 block (best-effort, safe)
# We find the V7 block and patch within a limited window after the marker.
m = re.search(r"/\*\s*=====\s*VSP_P1_DASH_MINICHARTS_V7_ONLY_SAFE_V1[\s\S]{0,20000}", s)
if not m:
    raise SystemExit("[ERR] Could not locate V7 block window")

win = m.group(0)

# patch/insert fetchRidLatest + update main() rid logic
# 1) replace function getRID(){...}
new_getrid = r"""
    function getRID(){
      try{
        var u = new URL(location.href);
        var rid = u.searchParams.get("rid") || u.searchParams.get("RID") || "";
        rid = (rid||"").trim();
        if (rid && rid !== "YOUR_RID") return rid;
      }catch(e){}
      // try cached
      try{
        var cr = (window.__VSP_RID||"").toString().trim();
        if (cr && cr !== "YOUR_RID") return cr;
      }catch(e){}
      // cheap DOM sniff (bounded)
      var chips = qsa("a,button,span,div").slice(0,140);
      for(var i=0;i<chips.length;i++){
        var t=(chips[i].textContent||"").trim();
        if(t.startsWith("VSP_") && t.length<80 && t!=="YOUR_RID") return t;
        if(t.includes("RID:")){
          var mm=t.match(/RID:\s*([A-Za-z0-9_:-]{6,80})/);
          if(mm && mm[1] && mm[1]!=="YOUR_RID") return mm[1];
        }
      }
      return "";
    }
"""
win2 = re.sub(r"function\s+getRID\s*\(\)\s*\{[\s\S]*?\n\s*\}\n", new_getrid+"\n", win, count=1)

# 2) ensure fetchRidLatest exists (insert right after getRID)
if "async function fetchRidLatest" not in win2:
    ins = r"""
    async function fetchRidLatest(){
      var ctrl = new AbortController();
      var to = setTimeout(function(){ try{ctrl.abort();}catch(e){} }, 1500);
      try{
        var r = await fetch("/api/vsp/rid_latest", {credentials:"same-origin", signal: ctrl.signal});
        var j = await r.json().catch(function(){ return null; });
        var rid = (j && (j.rid||j.RID) || "").toString().trim();
        if (rid && rid !== "YOUR_RID") return rid;
      }catch(e){}
      finally{ clearTimeout(to); }
      return "";
    }
"""
    # place after getRID function
    win2 = re.sub(r"(function\s+getRID\s*\(\)[\s\S]*?\n\s*\}\n)", r"\1\n"+ins+"\n", win2, count=1)

# 3) patch main(): rid fallback to rid_latest when missing/YOUR_RID
win3 = win2
win3 = re.sub(
    r"var rid\s*=\s*getRID\(\);\s*",
    "var rid = getRID();\n      if(!rid || rid==='YOUR_RID'){ try{ rid = await fetchRidLatest() || rid; }catch(e){} }\n",
    win3,
    count=1
)

# 4) If fetchTop() builds URL, keep but ensure we don't append rid=YOUR_RID
win3 = re.sub(r"if\(rid\)\s*u\s*\+\=\s*\"&rid=\"",
              "if(rid && rid!=='YOUR_RID') u += \"&rid=\"",
              win3, count=1)

# swap back
s_new = s[:m.start()] + win3 + s[m.start()+len(win):]
p.write_text(s_new, encoding="utf-8")
print("[OK] patched V7 to auto rid_latest when rid missing/YOUR_RID")
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS"; exit 2; }

echo "[DONE] Ctrl+Shift+R: http://127.0.0.1:8910/vsp5  (no need rid param)"
