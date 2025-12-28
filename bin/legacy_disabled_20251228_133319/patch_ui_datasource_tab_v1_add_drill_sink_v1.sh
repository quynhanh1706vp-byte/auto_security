#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_drillsink_${TS}"
echo "[BACKUP] $F.bak_drillsink_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="// === VSP_DS_DRILLDOWN_SINK_V1_FOR_TAB_V1 ==="
if TAG in t:
    print("[OK] drill sink already present"); raise SystemExit(0)

t += "\n\n" + TAG + r"""
(function(){
  const KEY = "vsp_ds_drill_url_v1";

  function pane(){
    return document.getElementById("vsp-pane-datasource") || document.body;
  }

  function ensureBox(){
    let box = document.getElementById("vsp_ds_drill_box_v1");
    if(!box){
      box = document.createElement("div");
      box.id = "vsp_ds_drill_box_v1";
      box.style.marginTop = "10px";
      box.style.padding = "10px";
      box.style.borderRadius = "14px";
      box.style.border = "1px solid rgba(255,255,255,.10)";
      box.style.background = "rgba(0,0,0,.25)";
      box.innerHTML = `
        <div style="display:flex;gap:10px;align-items:center;justify-content:space-between;">
          <div style="font-weight:700;letter-spacing:.2px;">Drill Result</div>
          <button id="vsp_ds_drill_clear_v1" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#fff;cursor:pointer;">Clear</button>
        </div>
        <div id="vsp_ds_drill_url_v1" style="opacity:.7;font-size:12px;margin-top:6px;word-break:break-all;"></div>
        <pre id="vsp_ds_drill_pre_v1" style="white-space:pre-wrap;word-break:break-word;font-size:12px;line-height:1.35;margin:10px 0 0 0;"></pre>
      `;
      // insert near top of datasource pane
      const p = pane();
      p.insertBefore(box, p.children[1] || null);
      document.getElementById("vsp_ds_drill_clear_v1").onclick = ()=>{
        try{ sessionStorage.removeItem(KEY); }catch(e){}
        document.getElementById("vsp_ds_drill_url_v1").textContent = "";
        document.getElementById("vsp_ds_drill_pre_v1").textContent = "";
      };
    }
    return box;
  }

  async function renderFromUrl(url){
    if(!url) return;
    ensureBox();
    const urlEl = document.getElementById("vsp_ds_drill_url_v1");
    const preEl = document.getElementById("vsp_ds_drill_pre_v1");
    urlEl.textContent = url;
    preEl.textContent = "Loading…";

    try{
      const r = await fetch(url, {credentials:"same-origin"});
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      if(!ct.includes("application/json")){
        const tx = await r.text();
        preEl.textContent = "Non-JSON response\n\n" + tx.slice(0, 6000);
        return;
      }
      const j = await r.json();
      preEl.textContent = JSON.stringify(j, null, 2);
    }catch(e){
      preEl.textContent = "ERR: " + String(e);
    }
  }

  // API for dashboard to call
  window.VSP_DS_APPLY_DRILL_URL_V1 = function(url){
    try{ sessionStorage.setItem(KEY, url); }catch(e){}
    renderFromUrl(url);
  };

  function autoApplyIfDatasource(){
    const h = String(location.hash||"");
    if(!h.toLowerCase().includes("datasource")) return;
    let url=null;
    try{ url = sessionStorage.getItem(KEY); }catch(e){}
    if(url) setTimeout(()=>renderFromUrl(url), 200);
  }

  window.addEventListener("load", autoApplyIfDatasource);
  window.addEventListener("hashchange", autoApplyIfDatasource);
})();
"""
p.write_text(t, encoding="utf-8")
print("[OK] appended drill sink to", p)
PY

echo "[DONE] patched. Now hard refresh (Ctrl+Shift+R)."
