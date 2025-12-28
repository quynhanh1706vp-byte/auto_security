#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

BUNDLE="static/js/vsp_bundle_commercial_v2.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_dash_toolbar_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_dash_toolbar_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_DASH_RID_TOOLBAR_AUTOSYNC_V1"
if marker in s:
    print("[OK] toolbar already present")
    raise SystemExit(0)

addon = r"""
/* VSP_P0_DASH_RID_TOOLBAR_AUTOSYNC_V1 */
(()=> {
  if (window.__vsp_p0_dash_rid_toolbar_autosync_v1) return;
  window.__vsp_p0_dash_rid_toolbar_autosync_v1 = true;

  const isDash = ()=> {
    try{
      const p = (location.pathname||"");
      return p === "/vsp5" || p.startsWith("/vsp5/");
    }catch(e){ return false; }
  };

  const LS_RID = "vsp_selected_rid";
  const LS_AUTO = "vsp_dash_auto_latest"; // "1" or "0"

  function getPinnedRid(){
    try{ return (localStorage.getItem(LS_RID)||"").trim(); }catch(e){ return ""; }
  }
  function setPinnedRid(rid){
    try{ localStorage.setItem(LS_RID, String(rid||"").trim()); }catch(e){}
  }

  function setRidGlobal(rid, why){
    const r = String(rid||"").trim();
    if (!r) return;
    try{ window.__VSP_SELECTED_RID = r; }catch(e){}
    setPinnedRid(r);
    try{
      window.dispatchEvent(new CustomEvent("vsp:rid", {detail:{rid:r, why: why||"setRidGlobal"}}));
    }catch(e){}
  }

  async function getLatestRid(){
    try{
      const r = await fetch("/api/vsp/latest_rid", {credentials:"same-origin"});
      if (!r.ok) return null;
      const j = await r.json();
      if (j && j.ok && j.rid) return j;
    }catch(e){}
    return null;
  }

  function el(tag, attrs, html){
    const x = document.createElement(tag);
    if (attrs){
      for (const k of Object.keys(attrs)){
        if (k === "class") x.className = attrs[k];
        else if (k === "style") x.setAttribute("style", attrs[k]);
        else x.setAttribute(k, attrs[k]);
      }
    }
    if (html != null) x.innerHTML = html;
    return x;
  }

  function css(){
    return `
#vspRidBar{
  position: sticky; top: 0; z-index: 9999;
  margin: 10px 0 0 0;
  padding: 10px 12px;
  border-radius: 12px;
  background: rgba(10, 16, 28, 0.85);
  border: 1px solid rgba(255,255,255,0.08);
  backdrop-filter: blur(8px);
}
#vspRidBar .row{display:flex; align-items:center; gap:10px; flex-wrap:wrap;}
#vspRidBar .pill{
  padding: 6px 10px; border-radius: 999px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(255,255,255,0.04);
  font-size: 12px;
}
#vspRidBar input{
  min-width: 360px;
  padding: 8px 10px;
  border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(0,0,0,0.25);
  color: #e9eefc;
  outline: none;
}
#vspRidBar button{
  padding: 8px 10px;
  border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(255,255,255,0.04);
  color: #e9eefc;
  cursor: pointer;
}
#vspRidBar button:hover{ background: rgba(255,255,255,0.07); }
#vspRidBar .muted{opacity:0.75; font-size:12px;}
#vspRidBar .ok{color:#90ee90;}
#vspRidBar .warn{color:#ffd27d;}
`;
  }

  function installBar(){
    const host = document.querySelector(".vsp5-shell, body") || document.body;
    if (!host || document.getElementById("vspRidBar")) return;

    const style = el("style", null, css());
    document.head.appendChild(style);

    const bar = el("div", {id:"vspRidBar"});
    bar.innerHTML = `
      <div class="row">
        <span class="pill">RID</span>
        <input id="vspRidInput" spellcheck="false" placeholder="VSP_CI_YYYYmmdd_HHMMSS" />
        <button id="vspRidUse">Use RID</button>
        <button id="vspRidLatest">Sync latest</button>
        <button id="vspRidCopy">Copy</button>
        <label class="pill" style="display:flex; gap:8px; align-items:center;">
          <input id="vspRidAuto" type="checkbox" style="min-width:auto; width:16px; height:16px;" />
          Auto latest (30s)
        </label>
        <span id="vspRidStatus" class="muted">…</span>
      </div>
      <div class="row" style="margin-top:8px;">
        <span class="muted">Tip:</span>
        <span class="muted">Pin RID in localStorage + broadcast <code>vsp:rid</code> so GateStory/Panels refresh together.</span>
      </div>
    `;

    // Insert near top of body content (after tabs if present)
    const first = document.body.firstElementChild;
    if (first) first.insertAdjacentElement("afterend", bar);
    else document.body.prepend(bar);

    const $rid = bar.querySelector("#vspRidInput");
    const $use = bar.querySelector("#vspRidUse");
    const $latest = bar.querySelector("#vspRidLatest");
    const $copy = bar.querySelector("#vspRidCopy");
    const $auto = bar.querySelector("#vspRidAuto");
    const $st = bar.querySelector("#vspRidStatus");

    const pinned = getPinnedRid() || String(window.__VSP_SELECTED_RID||"").trim();
    if (pinned) $rid.value = pinned;

    const autoOn = (()=>{ try{return (localStorage.getItem(LS_AUTO)||"1")==="1";}catch(e){return true;} })();
    $auto.checked = autoOn;

    function setStatus(msg, cls){
      $st.textContent = msg;
      $st.className = "muted " + (cls||"");
    }

    $use.addEventListener("click", ()=> {
      const r = ($rid.value||"").trim();
      if (!r) return setStatus("RID empty", "warn");
      setRidGlobal(r, "toolbar_use");
      setStatus("Pinned RID = " + r, "ok");
    });

    $latest.addEventListener("click", async ()=> {
      setStatus("Syncing latest…");
      const j = await getLatestRid();
      if (!j) return setStatus("latest_rid not available", "warn");
      $rid.value = j.rid;
      setRidGlobal(j.rid, "toolbar_latest");
      setStatus("Latest RID = " + j.rid, "ok");
    });

    $copy.addEventListener("click", async ()=> {
      const r = ($rid.value||"").trim();
      try{
        await navigator.clipboard.writeText(r);
        setStatus("Copied", "ok");
      }catch(e){
        setStatus("Copy failed", "warn");
      }
    });

    $auto.addEventListener("change", ()=> {
      try{ localStorage.setItem(LS_AUTO, $auto.checked ? "1" : "0"); }catch(e){}
      setStatus("Auto latest = " + ($auto.checked ? "ON" : "OFF"));
    });

    // keep input in sync when something else sets rid
    window.addEventListener("vsp:rid", (e)=> {
      try{
        const r = String(e && e.detail && e.detail.rid ? e.detail.rid : "").trim();
        if (!r) return;
        $rid.value = r;
        setStatus("RID event: " + r, "ok");
      }catch(_){}
    });

    setStatus("Ready", "ok");
  }

  async function autoLoop(){
    // commercial: always follow latest run if enabled
    for(;;){
      await new Promise(r=> setTimeout(r, 30000));
      if (!isDash()) continue;
      let autoOn = true;
      try{ autoOn = (localStorage.getItem(LS_AUTO)||"1")==="1"; }catch(e){}
      if (!autoOn) continue;

      const j = await getLatestRid();
      if (!j || !j.rid) continue;

      const cur = String(window.__VSP_SELECTED_RID||"").trim() || getPinnedRid();
      if (cur !== j.rid){
        setRidGlobal(j.rid, "auto_latest");
      }
    }
  }

  function boot(){
    if (!isDash()) return;
    installBar();
    // initial: if nothing pinned -> sync latest once
    (async ()=>{
      const cur = String(window.__VSP_SELECTED_RID||"").trim() || getPinnedRid();
      if (!cur){
        const j = await getLatestRid();
        if (j && j.rid) setRidGlobal(j.rid, "boot_latest");
      }
    })();
    autoLoop();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended dashboard RID toolbar + autosync to bundle")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$BUNDLE" && echo "[OK] node --check bundle OK"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
