#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drilldown_p1_${TS}" && echo "[BACKUP] $F.bak_drilldown_p1_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_DASH_DRILLDOWN_P1_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
/* VSP_DASH_DRILLDOWN_P1_V1: openable drilldown panel for Degraded + Overrides */
(function(){
  'use strict';

  async function _j(url, timeoutMs=8000){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: ctrl.signal, headers:{'Accept':'application/json'}});
      const ct = (r.headers.get('content-type')||'').toLowerCase();
      if(!ct.includes('application/json')) return null;
      return await r.json();
    }catch(e){
      return null;
    }finally{
      clearTimeout(t);
    }
  }

  function _getRidFromLocal(){
    const keys = ["vsp_selected_rid_v2","vsp_selected_rid","vsp_current_rid","VSP_RID","vsp_rid"];
    for(const k of keys){
      try{
        const v = localStorage.getItem(k);
        if(v && v !== "null" && v !== "undefined") return v;
      }catch(e){}
    }
    return null;
  }

  async function _getRid(){
    try{
      if(window.VSP_RID && typeof window.VSP_RID.get === "function"){
        const r = window.VSP_RID.get();
        if(r) return r;
      }
    }catch(e){}
    const l = _getRidFromLocal();
    if(l) return l;
    const x = await _j("/api/vsp/latest_rid_v1");
    if(x && x.ok && x.run_id) return x.run_id;
    return null;
  }

  function _ensureUI(){
    if(document.getElementById("vsp-dd-overlay")) return;

    const st = document.createElement("style");
    st.id = "vsp-dd-style";
    st.textContent = `
      #vsp-dd-overlay{position:fixed;inset:0;z-index:10000;background:rgba(0,0,0,.55);display:none;}
      #vsp-dd-panel{position:fixed;top:60px;right:18px;bottom:18px;width:min(820px,calc(100vw - 36px));
        z-index:10001;background:rgba(2,6,23,.96);border:1px solid rgba(148,163,184,.18);border-radius:18px;
        box-shadow:0 20px 80px rgba(0,0,0,.55);display:none;overflow:hidden;}
      #vsp-dd-head{display:flex;align-items:center;justify-content:space-between;padding:14px 14px;border-bottom:1px solid rgba(148,163,184,.14);}
      #vsp-dd-title{font-weight:800;color:#e2e8f0;font-size:14px;letter-spacing:.2px}
      #vsp-dd-actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
      .vsp-dd-btn{padding:7px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.22);background:rgba(15,23,42,.55);
        color:#cbd5e1;font-size:12px;cursor:pointer}
      .vsp-dd-btn:hover{filter:brightness(1.08)}
      #vsp-dd-body{padding:14px;overflow:auto;height:calc(100% - 56px);color:#cbd5e1}
      .vsp-dd-card{border:1px solid rgba(148,163,184,.14);border-radius:16px;background:rgba(15,23,42,.35);padding:12px 12px;margin-bottom:12px;}
      .vsp-dd-kv{display:grid;grid-template-columns:160px 1fr;gap:6px 12px;font-size:12px;}
      .vsp-dd-k{opacity:.85}
      .vsp-dd-v{color:#e2e8f0}
      .vsp-dd-table{width:100%;border-collapse:separate;border-spacing:0 8px;font-size:12px;}
      .vsp-dd-table td{padding:8px 10px;border:1px solid rgba(148,163,184,.14);background:rgba(2,6,23,.35);}
      .vsp-dd-table tr td:first-child{border-radius:12px 0 0 12px;}
      .vsp-dd-table tr td:last-child{border-radius:0 12px 12px 0;}
      .vsp-dd-muted{opacity:.75}
      .vsp-dd-link{color:#93c5fd;text-decoration:none}
      .vsp-dd-link:hover{text-decoration:underline}
      code.vsp-dd-code{background:rgba(2,6,23,.6);border:1px solid rgba(148,163,184,.16);padding:2px 6px;border-radius:8px}
    `;
    document.head.appendChild(st);

    const ov = document.createElement("div");
    ov.id="vsp-dd-overlay";
    ov.addEventListener("click", close);
    document.body.appendChild(ov);

    const panel = document.createElement("div");
    panel.id="vsp-dd-panel";
    panel.innerHTML = `
      <div id="vsp-dd-head">
        <div id="vsp-dd-title">Drilldown</div>
        <div id="vsp-dd-actions">
          <button class="vsp-dd-btn" id="vsp-dd-refresh">Refresh</button>
          <button class="vsp-dd-btn" id="vsp-dd-copy">Copy RID</button>
          <button class="vsp-dd-btn" id="vsp-dd-close">Close</button>
        </div>
      </div>
      <div id="vsp-dd-body">
        <div class="vsp-dd-card"><div class="vsp-dd-muted">Loading…</div></div>
      </div>
    `;
    document.body.appendChild(panel);

    document.getElementById("vsp-dd-close").addEventListener("click", close);
    document.getElementById("vsp-dd-refresh").addEventListener("click", render);
    document.getElementById("vsp-dd-copy").addEventListener("click", async ()=>{
      const rid = await _getRid();
      try{ await navigator.clipboard.writeText(rid||""); }catch(e){}
    });

    window.addEventListener("keydown", (e)=>{
      if(e.key === "Escape") close();
    });
  }

  function open(){
    _ensureUI();
    document.getElementById("vsp-dd-overlay").style.display="block";
    document.getElementById("vsp-dd-panel").style.display="block";
    render();
  }

  function close(){
    const ov=document.getElementById("vsp-dd-overlay");
    const pn=document.getElementById("vsp-dd-panel");
    if(ov) ov.style.display="none";
    if(pn) pn.style.display="none";
  }

  function _fmtOverrides(eff){
    const d = (eff && eff.delta) ? eff.delta : {};
    const matched = d.matched_n ?? 0;
    const applied = d.applied_n ?? 0;
    const sup = d.suppressed_n ?? 0;
    const chg = d.changed_severity_n ?? 0;
    const exp = d.expired_match_n ?? 0;
    return {matched, applied, sup, chg, exp, now_utc: d.now_utc || ""};
  }

  function _htmlEscape(x){
    return String(x||"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));
  }

  async function render(){
    _ensureUI();
    const body = document.getElementById("vsp-dd-body");
    const title = document.getElementById("vsp-dd-title");
    const rid = await _getRid();
    title.textContent = rid ? `Drilldown • ${rid}` : "Drilldown • (no RID)";

    if(!rid){
      body.innerHTML = `<div class="vsp-dd-card"><div class="vsp-dd-muted">No RID selected.</div></div>`;
      return;
    }

    body.innerHTML = `<div class="vsp-dd-card"><div class="vsp-dd-muted">Loading ${_htmlEscape(rid)}…</div></div>`;

    const [st, eff, art] = await Promise.all([
      _j(`/api/vsp/run_status_v2/${encodeURIComponent(rid)}`),
      _j(`/api/vsp/findings_effective_v1/${encodeURIComponent(rid)}?limit=0`),
      _j(`/api/vsp/run_artifacts_index_v1/${encodeURIComponent(rid)}`)
    ]);

    const degraded = (st && st.degraded_tools) ? st.degraded_tools : [];
    const ov = _fmtOverrides(eff);

    let artHtml = `<div class="vsp-dd-muted">Artifacts: n/a</div>`;
    if(art && (art.ok || art.items)){
      const items = art.items || [];
      const links = items.slice(0,10).map(it=>{
        const name = _htmlEscape(it.name || it.file || "artifact");
        const url  = it.url || it.href || it.download_url || "";
        if(url) return `<a class="vsp-dd-link" href="${_htmlEscape(url)}" target="_blank" rel="noopener">${name}</a>`;
        return `<span class="vsp-dd-muted">${name}</span>`;
      });
      artHtml = `<div class="vsp-dd-muted">Artifacts:</div><div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:6px;">${links.join(" ") || '<span class="vsp-dd-muted">empty</span>'}</div>`;
    }

    const degradedRows = (degraded||[]).map(it=>{
      const tool=_htmlEscape(it.tool || it.name || "");
      const verdict=_htmlEscape(it.verdict || "");
      const rc=(it.rc!==undefined && it.rc!==null) ? _htmlEscape(it.rc) : "";
      const reason=_htmlEscape(it.reason || it.error || it.note || "");
      return `<tr>
        <td><b>${tool}</b></td>
        <td>${verdict || '<span class="vsp-dd-muted">—</span>'}</td>
        <td>${rc || '<span class="vsp-dd-muted">—</span>'}</td>
        <td>${reason || '<span class="vsp-dd-muted">—</span>'}</td>
      </tr>`;
    }).join("");

    body.innerHTML = `
      <div class="vsp-dd-card">
        <div style="font-weight:800;color:#e2e8f0;margin-bottom:8px;">Overview</div>
        <div class="vsp-dd-kv">
          <div class="vsp-dd-k">RID</div><div class="vsp-dd-v"><code class="vsp-dd-code">${_htmlEscape(rid)}</code></div>
          <div class="vsp-dd-k">Overrides delta</div><div class="vsp-dd-v">matched=${ov.matched} • applied=${ov.applied} • suppressed=${ov.sup} • changed=${ov.chg} • expired=${ov.exp}</div>
          <div class="vsp-dd-k">Delta time</div><div class="vsp-dd-v">${_htmlEscape(ov.now_utc) || '<span class="vsp-dd-muted">—</span>'}</div>
          <div class="vsp-dd-k">Degraded tools</div><div class="vsp-dd-v">${(degraded||[]).length || 0}</div>
        </div>
        <div style="margin-top:10px;">${artHtml}</div>
      </div>

      <div class="vsp-dd-card">
        <div style="font-weight:800;color:#e2e8f0;margin-bottom:8px;">Degraded details</div>
        ${(degraded && degraded.length) ? `
          <table class="vsp-dd-table">
            <tr>
              <td><b>Tool</b></td><td><b>Verdict</b></td><td><b>RC</b></td><td><b>Reason</b></td>
            </tr>
            ${degradedRows}
          </table>
        ` : `<div class="vsp-dd-muted">No degraded tools.</div>`}
      </div>
    `;
  }

  window.VSP_DASH_DRILLDOWN = { open, close, render };
})();
'''

p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended drilldown block")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_drilldown_p1_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
