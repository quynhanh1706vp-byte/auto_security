#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tabs4_autorid_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p63_${TS}"
echo "[OK] backup ${F}.bak_p63_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_tabs4_autorid_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="P63_AUTORID_RETRY_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

patch=r"""
/* P63_AUTORID_RETRY_V1 */
(function(){
  try{
    if (window.__VSP_AUTORID_PATCHED_P63) return;
    window.__VSP_AUTORID_PATCHED_P63 = true;

    async function _vspFetchLatestRid(){
      const urls=[
        "/api/vsp/top_findings_v2?limit=1",
        "/api/vsp/datasource?lite=1",
        "/api/vsp/trend_v1"
      ];
      for(let attempt=0; attempt<5; attempt++){
        for(const u of urls){
          try{
            const r = await fetch(u, {cache:"no-store", credentials:"same-origin"});
            const txt = await r.text();
            let j=null;
            try{ j = JSON.parse(txt); }catch(_){ continue; }
            const rid =
              (j && (j.rid || j.run_id)) ||
              (j && j.items && j.items[0] && (j.items[0].rid || j.items[0].run_id)) ||
              (j && j.points && j.points[0] && (j.points[0].rid || j.points[0].run_id)) ||
              "";
            if (rid) return rid;
          }catch(_){}
        }
        await new Promise(res=>setTimeout(res, 500*(attempt+1)));
      }
      return "";
    }

    window.__VSP_AUTORID_FETCH_LATEST = _vspFetchLatestRid;

    document.addEventListener("DOMContentLoaded", async ()=>{
      try{
        const u = new URL(location.href);
        const rid = u.searchParams.get("rid") || u.searchParams.get("run_id") || "";
        if (rid){
          try{ localStorage.setItem("VSP_LAST_RID", rid); }catch(_){}
          return;
        }
        if (u.searchParams.get("_autorid_p63")) return;

        let last="";
        try{ last = localStorage.getItem("VSP_LAST_RID") || ""; }catch(_){}
        if (last){
          u.searchParams.set("rid", last);
          u.searchParams.set("_autorid_p63","1");
          location.replace(u.toString());
          return;
        }

        const latest = await _vspFetchLatestRid();
        if (!latest) return;

        try{ localStorage.setItem("VSP_LAST_RID", latest); }catch(_){}
        u.searchParams.set("rid", latest);
        u.searchParams.set("_autorid_p63","1");
        location.replace(u.toString());
      }catch(_){}
    });
  }catch(_){}
})();
"""

p.write_text(s + "\n" + patch + "\n", encoding="utf-8")
print("[OK] patched", p)
PY

echo "[DONE] P63 applied. Hard refresh: Ctrl+Shift+R"
