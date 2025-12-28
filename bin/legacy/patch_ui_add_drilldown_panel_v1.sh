#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_drillpanel_${TS}"
echo "[BACKUP] $F.bak_drillpanel_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_enhance_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="// === VSP_UI_DRILL_PANEL_V1 ==="
if TAG in t:
    print("[OK] drill panel already present"); raise SystemExit(0)

t += "\n\n" + TAG + r"""
(function(){
  const KEY = "vsp_ds_drill_url_v1";

  function setDrillUrl(url){
    try{ sessionStorage.setItem(KEY, url); }catch(e){}
  }
  function gotoDatasource(){
    const h = String(location.hash||"");
    if(h.startsWith("#vsp4-")) location.hash = "#vsp4-datasource";
    else location.hash = "#datasource";
    try{ window.dispatchEvent(new Event("hashchange")); }catch(e){}
  }
  async function dashLatest(){
    const r = await fetch("/api/vsp/dashboard_latest_v1", {credentials:"same-origin"});
    return await r.json();
  }

  function ensurePanel(d){
    const id="vsp_drill_panel_v1";
    if(document.getElementById(id)) return;

    const wrap=document.createElement("div");
    wrap.id=id;
    wrap.style.position="fixed";
    wrap.style.right="18px";
    wrap.style.bottom="18px";
    wrap.style.zIndex="9999";
    wrap.style.padding="10px";
    wrap.style.borderRadius="14px";
    wrap.style.border="1px solid rgba(255,255,255,.10)";
    wrap.style.background="rgba(2,6,23,.78)";
    wrap.style.backdropFilter="blur(10px)";
    wrap.style.boxShadow="0 10px 30px rgba(0,0,0,.35)";
    wrap.style.fontSize="12px";
    wrap.style.color="rgba(255,255,255,.85)";
    wrap.innerHTML = `
      <div style="font-weight:700;margin-bottom:6px;">Drilldown</div>
      <div style="display:flex;gap:8px;flex-wrap:wrap;">
        <button id="vsp_drill_total" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#fff;cursor:pointer;">TOTAL</button>
        <button id="vsp_drill_critical" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#fff;cursor:pointer;">CRITICAL</button>
        <button id="vsp_drill_high" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#fff;cursor:pointer;">HIGH</button>
      </div>
      <div style="opacity:.65;margin-top:6px;">(opens Data Source)</div>
    `;
    document.body.appendChild(wrap);

    const links = (d && d.links) ? d.links : {};
    const sev = (links.severity)||{};
    function bind(btnId, url){
      const b=document.getElementById(btnId);
      if(!b) return;
      b.onclick = ()=>{
        if(!url){ console.warn("[DRILL] missing url for", btnId); return; }
        setDrillUrl(url);
        gotoDatasource();
        if(typeof window.VSP_DS_APPLY_DRILL_URL_V1==="function"){
          try{ window.VSP_DS_APPLY_DRILL_URL_V1(url); }catch(e){}
        }
        console.log("[DRILL] open", url);
      };
    }
    bind("vsp_drill_total", links.all);
    bind("vsp_drill_critical", sev.CRITICAL);
    bind("vsp_drill_high", sev.HIGH);
  }

  window.addEventListener("load", async ()=>{
    try{
      const d = await dashLatest();
      window.__VSP_DASH_LATEST_V1 = d;
      ensurePanel(d);
    }catch(e){
      console.warn("[DRILL_PANEL] failed", e);
    }
  });
})();
"""
p.write_text(t, encoding="utf-8")
print("[OK] appended drill panel")
PY

echo "[DONE] Patch applied. Now hard refresh browser (Ctrl+Shift+R)."
