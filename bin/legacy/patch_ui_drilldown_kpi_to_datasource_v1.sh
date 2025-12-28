#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

DASH_JS="static/js/vsp_dashboard_enhance_v1.js"
DS_JS="static/js/vsp_datasource_tab_simple_v1.js"

[ -f "$DASH_JS" ] || { echo "[ERR] missing $DASH_JS"; exit 2; }
[ -f "$DS_JS" ] || { echo "[ERR] missing $DS_JS"; exit 2; }

cp -f "$DASH_JS" "$DASH_JS.bak_drill_${TS}"
cp -f "$DS_JS"   "$DS_JS.bak_drill_${TS}"
echo "[BACKUP] $DASH_JS.bak_drill_${TS}"
echo "[BACKUP] $DS_JS.bak_drill_${TS}"

python3 - <<'PY'
from pathlib import Path

# ---------- patch dashboard enhance ----------
p = Path("static/js/vsp_dashboard_enhance_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")
TAG = "// === VSP_UI_KPI_DRILLDOWN_V1 ==="
if TAG not in t:
    t += "\n\n" + TAG + r"""
(function(){
  const KEY = "vsp_ds_drill_url_v1";

  async function loadDashLatest(){
    try{
      const r = await fetch("/api/vsp/dashboard_latest_v1", {credentials:"same-origin"});
      const j = await r.json();
      window.__VSP_DASH_LATEST_V1 = j;
      return j;
    }catch(e){
      console.warn("[KPI_DRILLDOWN] loadDashLatest failed", e);
      return null;
    }
  }

  function _setDrillUrl(url){
    try{ sessionStorage.setItem(KEY, url); }catch(e){}
  }

  function openDrill(url){
    if(!url) return;
    _setDrillUrl(url);

    // best-effort: switch tab by hash
    try{
      if(!String(location.hash||"").toLowerCase().includes("datasource")){
        location.hash = "#datasource";
        // kick router if it listens
        setTimeout(()=>{ try{ window.dispatchEvent(new Event("hashchange")); }catch(e){} }, 50);
      }
    }catch(e){}

    // if Data Source JS installed hook -> use it
    if(typeof window.VSP_DS_APPLY_DRILL_URL_V1 === "function"){
      try{ window.VSP_DS_APPLY_DRILL_URL_V1(url); return; }catch(e){}
    }

    // fallback: open API in new tab (always works)
    try{ window.open(url, "_blank"); }catch(e){}
  }

  function bindClicks(dash){
    if(!dash || !dash.links) return;

    const sevLinks = (dash.links.severity || {});
    const allUrl   = dash.links.all;

    const nodes = Array.from(document.querySelectorAll("a,button,div,section,article,span"))
      .filter(el=>{
        const txt = (el.innerText||"").trim();
        return txt && txt.length > 0 && txt.length < 160;
      });

    function attachByKeyword(keywordUpper, url, title){
      if(!url) return;
      for(const el of nodes){
        const txt = (el.innerText||"").toUpperCase();
        if(!txt.includes(keywordUpper)) continue;
        if(el.__vsp_drill_attached) continue;
        el.__vsp_drill_attached = true;
        el.style.cursor = "pointer";
        el.title = title;
        el.addEventListener("click", (ev)=>{
          // allow user open normally with ctrl/cmd
          if(ev && (ev.ctrlKey || ev.metaKey || ev.shiftKey)) return;
          try{ ev.preventDefault(); }catch(e){}
          openDrill(url);
        });
      }
    }

    // severity KPI cards (by keyword)
    ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(sev=>{
      attachByKeyword(sev, sevLinks[sev], `Drilldown → ${sev}`);
    });

    // total findings KPI (heuristic)
    if(allUrl){
      for(const el of nodes){
        const txt = (el.innerText||"").toUpperCase();
        const hit = (txt.includes("TOTAL") && (txt.includes("FIND") || txt.includes("FINDINGS"))) || txt.includes("TOTAL FINDINGS");
        if(!hit) continue;
        if(el.__vsp_drill_total) continue;
        el.__vsp_drill_total = true;
        el.style.cursor = "pointer";
        el.title = "Drilldown → ALL findings";
        el.addEventListener("click", (ev)=>{
          if(ev && (ev.ctrlKey || ev.metaKey || ev.shiftKey)) return;
          try{ ev.preventDefault(); }catch(e){}
          openDrill(allUrl);
        });
      }
    }

    // expose helper for manual use
    window.VSP_DASH_OPEN_DRILL_V1 = openDrill;
    console.log("[KPI_DRILLDOWN] bound", {rid: dash.rid, hasLinks: !!dash.links});
  }

  window.addEventListener("load", async ()=>{
    const dash = await loadDashLatest();
    // wait a bit so DOM cards exist
    setTimeout(()=>bindClicks(dash), 600);
  });
})();
""" + "\n"
    p.write_text(t, encoding="utf-8")
    print("[OK] patched", p)
else:
    print("[OK] dashboard drilldown already present")

# ---------- patch datasource tab ----------
p2 = Path("static/js/vsp_datasource_tab_simple_v1.js")
t2 = p2.read_text(encoding="utf-8", errors="ignore")
TAG2 = "// === VSP_DS_DRILLDOWN_SINK_V1 ==="
if TAG2 not in t2:
    t2 += "\n\n" + TAG2 + r"""
(function(){
  const KEY = "vsp_ds_drill_url_v1";

  function hostEl(){
    return (
      document.querySelector("#tab-datasource") ||
      document.querySelector("#tab_datasource") ||
      document.querySelector("#datasource") ||
      document.querySelector("[data-tab='datasource']") ||
      document.body
    );
  }

  function ensurePre(){
    let pre = document.getElementById("vsp_ds_pre_v1");
    if(!pre){
      pre = document.createElement("pre");
      pre.id = "vsp_ds_pre_v1";
      pre.style.whiteSpace = "pre-wrap";
      pre.style.wordBreak = "break-word";
      pre.style.fontSize = "12px";
      pre.style.lineHeight = "1.35";
      pre.style.marginTop = "12px";
      pre.style.padding = "10px";
      pre.style.borderRadius = "12px";
      pre.style.border = "1px solid rgba(255,255,255,.10)";
      pre.style.background = "rgba(0,0,0,.25)";
      hostEl().appendChild(pre);
    }
    return pre;
  }

  async function refreshFromUrl(url){
    if(!url) return;
    const pre = ensurePre();
    pre.textContent = "Loading drilldown…\n" + url;

    try{
      const r = await fetch(url, {credentials:"same-origin"});
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      if(!ct.includes("application/json")){
        const tx = await r.text();
        pre.textContent = "Non-JSON response\n\n" + tx.slice(0, 4000);
        return;
      }
      const j = await r.json();
      pre.textContent = JSON.stringify(j, null, 2);
    }catch(e){
      pre.textContent = "ERR: " + String(e);
    }
  }

  // called by dashboard click
  window.VSP_DS_APPLY_DRILL_URL_V1 = function(url){
    try{ sessionStorage.setItem(KEY, url); }catch(e){}
    refreshFromUrl(url);
  };

  // auto-apply when entering datasource tab (or on load)
  window.addEventListener("load", ()=>{
    let url = null;
    try{ url = sessionStorage.getItem(KEY); }catch(e){}
    if(url){
      setTimeout(()=>refreshFromUrl(url), 400);
    }
  });
})();
""" + "\n"
    p2.write_text(t2, encoding="utf-8")
    print("[OK] patched", p2)
else:
    print("[OK] datasource drilldown sink already present")
PY

echo "[DONE] UI drilldown patched. Please hard refresh browser (Ctrl+Shift+R)."
