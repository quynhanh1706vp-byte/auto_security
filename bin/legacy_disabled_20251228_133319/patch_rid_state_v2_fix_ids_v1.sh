#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_rid_state_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "$JS.bak_ridv2_${TS}"
echo "[BACKUP] $JS.bak_ridv2_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_rid_state_v1.js")
p.write_text(r"""/* VSP_RID_STATE_V2: global RID state (localStorage + auto pick latest + export capture bind) */
(function(){
  const KEY = "VSP_CURRENT_RID";
  const RID_RE = /(RUN_)?VSP_CI_\d{8}_\d{6}/;

  function normRid(rid){
    if(!rid) return "";
    rid = String(rid).trim();
    rid = rid.replace(/^RUN_/, "");
    if(!RID_RE.test(rid)) return "";
    return rid;
  }

  function get(){ return normRid(localStorage.getItem(KEY) || ""); }
  function set(rid){
    rid = normRid(rid);
    if(!rid) return false;
    localStorage.setItem(KEY, rid);
    window.dispatchEvent(new CustomEvent("vsp:rid-changed", { detail: { rid } }));
    return true;
  }
  function clear(){
    localStorage.removeItem(KEY);
    window.dispatchEvent(new CustomEvent("vsp:rid-changed", { detail: { rid: "" } }));
  }

  async function pickLatest(){
    try{
      const url = "/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1";
      const r = await fetch(url, { cache:"no-store" });
      if(!r.ok) return "";
      const j = await r.json();
      const ridRaw = (j && j.items && j.items[0] && j.items[0].run_id) ? j.items[0].run_id : "";
      const rid = normRid(String(ridRaw));
      if(rid) set(rid);
      return rid;
    }catch(e){
      console.warn("[VSP_RID_STATE_V2] pickLatest failed", e);
      return "";
    }
  }

  function updateHeader(){
    const rid = get();
    const el = document.getElementById("vsp-rid-label");
    if(el) el.textContent = rid ? ("RID: " + rid) : "RID: (none)";
  }

  async function ensure(){
    updateHeader();
    const cur = get();
    if(cur) return cur;
    const rid = await pickLatest();
    updateHeader();
    return rid;
  }

  function bindExportCapture(btnId, fmt){
    const b = document.getElementById(btnId);
    if(!b) return;
    if(b.dataset && b.dataset.vspExportBound === "1") return;
    if(b.dataset) b.dataset.vspExportBound = "1";

    b.addEventListener("click", async (e)=>{
      // CAPTURE: block old bubble listeners (your current go(fmt) handler)
      try{
        e.preventDefault();
        e.stopImmediatePropagation();
        e.stopPropagation();
      }catch(_){}

      const rid = await ensure();
      if(!rid) {
        console.warn("[VSP_RID_STATE_V2] no RID; cannot export");
        return;
      }
      const ridPath = "RUN_" + rid;
      window.location.href = `/api/vsp/run_export_v3/${ridPath}?fmt=${encodeURIComponent(fmt)}`;
    }, true); // <-- capture
  }

  function wireExports(){
    // your UI uses btn-export-*
    bindExportCapture("btn-export-html", "html");
    bindExportCapture("btn-export-zip",  "zip");
    bindExportCapture("btn-export-pdf",  "pdf");
    // backward compat if any old ids exist
    bindExportCapture("export-html", "html");
    bindExportCapture("export-zip",  "zip");
    bindExportCapture("export-pdf",  "pdf");
  }

  window.VSP_RID_STATE_V2 = { get, set, clear, ensure, pickLatest, updateHeader };

  window.addEventListener("vsp:rid-changed", updateHeader);
  document.addEventListener("DOMContentLoaded", async ()=>{
    wireExports();
    await ensure();
  });
})();""", encoding="utf-8")
print("[OK] wrote", str(p))
PY

echo "[OK] patched RID state to V2"
