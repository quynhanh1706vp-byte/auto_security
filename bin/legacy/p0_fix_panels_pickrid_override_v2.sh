#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_commercial_panels_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_pickrid_override_${TS}"
echo "[BACKUP] ${JS}.bak_pickrid_override_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_PANELS_PICKRID_OVERRIDE_V2"
if marker in s:
    print("[OK] override already present")
    raise SystemExit(0)

# inject near end of IIFE (before last })(); )
tail = s.rfind("})();")
if tail == -1:
    raise SystemExit("[ERR] cannot find IIFE end '})();'")

inject = r'''
/* VSP_P0_PANELS_PICKRID_OVERRIDE_V2 */
try{
  if (!window.__vsp_p0_panels_pickrid_override_v2){
    window.__vsp_p0_panels_pickrid_override_v2 = true;

    const __lsKeys = ["vsp_selected_rid","vsp_rid","VSP_RID","vsp5_rid","vsp_gate_story_rid"];
    const __tryLS = ()=> {
      try{
        for (const k of __lsKeys){
          const v = (localStorage.getItem(k)||"").trim();
          if (v) return v;
        }
      }catch(e){}
      return "";
    };

    const __tryLatest = async ()=> {
      try{
        const r = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
        if (!r.ok) return "";
        const j = await r.json();
        if (j && j.ok && j.rid) return String(j.rid);
      }catch(e){}
      return "";
    };

    // hard override: any call site using pickRidFromRunsApi(...) will now prefer selected/latest rid
    if (typeof pickRidFromRunsApi === "function" && !pickRidFromRunsApi.__vsp_overridden){
      const __orig = pickRidFromRunsApi;
      const __wrapped = async (...args)=> {
        try{
          const forced = (String(window.__VSP_SELECTED_RID||"").trim()) || __tryLS() || (await __tryLatest());
          if (forced) return forced;
        }catch(e){}
        return await __orig(...args);
      };
      __wrapped.__vsp_overridden = true;
      pickRidFromRunsApi = __wrapped;
    }

    // event-driven refresh
    window.addEventListener("vsp:rid", (e)=> {
      try{
        const r = String(e && e.detail && e.detail.rid ? e.detail.rid : "").trim();
        if (!r) return;
        window.__VSP_SELECTED_RID = r;
        try{ localStorage.setItem("vsp_selected_rid", r); }catch(_){}
        try{ if (typeof main === "function") main(); }catch(_){}
      }catch(_){}
    });

    // optional direct setter
    window.__vsp_panels_set_rid = (rid)=> {
      try{
        const r = String(rid||"").trim();
        if (!r) return;
        window.__VSP_SELECTED_RID = r;
        try{ localStorage.setItem("vsp_selected_rid", r); }catch(_){}
        try{ if (typeof main === "function") main(); }catch(_){}
      }catch(_){}
    };
  }
}catch(e){}
'''
s2 = s[:tail] + inject + "\n" + s[tail:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted pickRidFromRunsApi override + vsp:rid listener")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check $JS"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
