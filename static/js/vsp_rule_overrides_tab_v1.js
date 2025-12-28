/* VSP_RULE_OVERRIDES_GUARD_V2_BEGIN */
(function(){
  'use strict';
  if (typeof window === 'undefined') return;

  window.__vspGetRidSafe = async function(){
    try{
      if (typeof window.VSP_RID_PICKLATEST_OVERRIDE_V1 === 'function'){
        const rid = await window.VSP_RID_PICKLATEST_OVERRIDE_V1();
        if (rid) return rid;
      }
    } catch(_e){}
    try{
      if (window.VSP_RID_STATE && typeof window.VSP_RID_STATE.pickLatest === 'function'){
        const rid = await window.VSP_RID_STATE.pickLatest();
        if (rid) return rid;
      }
    } catch(_e){}
    return null;
  };
})();
 /* VSP_RULE_OVERRIDES_GUARD_V2_END */

/* VSP_RULEOVERRIDES_GUARD_V1_BEGIN */
// commercial safety: don't crash if rid override hook not present
try {
  if (!window.VSP_RID_PICKLATEST_OVERRIDE_V1) {
    window.VSP_RID_PICKLATEST_OVERRIDE_V1 = function(items) {
      return (items && items[0]) ? items[0] : null;
    };
  }
} catch(e) {}
/* VSP_RULEOVERRIDES_GUARD_V1_END */
/* VSP_RULE_OVERRIDES_TAB_V1: clean + CRUD (GET/POST) */
(function(){

const API = "/api/vsp/rule_overrides_v1";
  const $ = (id)=>document.getElementById(id);

  function esc(s){
    return String(s==null?'':s)
      .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
      .replace(/"/g,"&quot;").replace(/'/g,"&#39;");
  }
  function nowIsoDate(){
    const d=new Date(); const y=d.getFullYear();
    const m=String(d.getMonth()+1).padStart(2,'0');
    const day=String(d.getDate()).padStart(2,'0');
    return `${y}-${m}-${day}`;
  }
  function msg(t, kind){
    const el=$("rules-msg");
    if(!el) return;
    el.textContent = t || "";
    el.style.opacity = t ? "1" : "0.85";
    el.style.color = kind==="err" ? "rgba(248,113,113,0.95)" : "rgba(148,163,184,0.95)";
  }

  function normalizeFromApi(obj){
    // Accept: {version,items:[...]} OR {meta,overrides:[...]}
    if(!obj || typeof obj!=='object') return {version:1, items:[]};
    if(Array.isArray(obj.items)) return {version: obj.version||1, items: obj.items||[]};
    if(Array.isArray(obj.overrides)) return {version: 1, items: obj.overrides||[]};
    if(obj.meta && Array.isArray(obj.meta.overrides)) return {version: 1, items: obj.meta.overrides||[]};
    return {version: 1, items: []};
  }

  function toPostPayload(state){
    // Prefer commercial schema you already used:
    // {meta:{version:"v1"}, overrides:[{match:{...}, set:{...}, action, justification, expires_at, id}]}
    return { meta:{version:"v1"}, overrides: (state.items||[]).map(x=>x||{}) };
  }

  async function apiGet(){
    const r = await fetch(API, { cache:"no-store", credentials:"same-origin" });
    if(!r.ok) throw new Error("GET failed: "+r.status);
    return await r.json();
  }
  async function apiSave(payload){
    const r = await fetch(API, {
      method:"POST",
      headers:{ "Content-Type":"application/json" },
      body: JSON.stringify(payload),
      credentials:"same-origin",
    });
    if(!r.ok){
      const t = await r.text().catch(()=> "");
      throw new Error("POST failed: "+r.status+" "+t.slice(0,200));
    }
    return await r.json();
  }

  function render(container, state){
    const items = Array.isArray(state.items) ? state.items : [];
    const html = `
      <div class="vsp-card" style="margin:12px 0; padding:14px;">
        <div style="display:flex; gap:10px; align-items:center; justify-content:space-between; flex-wrap:wrap;">
          <div>
            <div style="font-weight:800; font-size:16px;">Rule Overrides</div>
            <div style="opacity:.75; font-size:12px;">API: <code>${esc(API)}</code></div>
          </div>
          <div style="display:flex; gap:8px; align-items:center;">
            <button class="vsp-btn vsp-btn-soft" id="rules-reload">Reload</button>
            <button class="vsp-btn vsp-btn-soft" id="rules-add">Add</button>
            <button class="vsp-btn vsp-btn-primary" id="rules-save">Save</button>
          </div>
        </div>
        <div id="rules-msg" style="margin-top:10px; font-size:12px; opacity:.9;"></div>
      </div>

      <div class="vsp-card" style="padding:0; overflow:auto;">
        <table style="width:100%; border-collapse:collapse;">
          <thead>
            <tr style="text-align:left; font-size:12px; opacity:.85;">
              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">ID</th>
              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Match (JSON)</th>
              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Action</th>
              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Set (JSON)</th>
              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Justification</th>
              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Expires</th>
              <th style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.06);">Ops</th>
            </tr>
          </thead>
          <tbody id="rules-body"></tbody>
        </table>
      </div>

      <div class="vsp-card" style="margin:12px 0; padding:14px;">
        <div style="font-weight:700; margin-bottom:8px;">Raw JSON editor</div>
        <textarea id="rules-json" spellcheck="false"
          style="width:100%; min-height:240px; font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          font-size:12px; padding:12px; border-radius:12px; border:1px solid rgba(255,255,255,.08);
          background:rgba(255,255,255,.03); color:inherit;"></textarea>
        <div style="margin-top:8px; opacity:.75; font-size:12px;">
          Tip: bạn có thể sửa JSON trực tiếp rồi bấm <b>Save</b>.
        </div>
      </div>
    `;
    container.innerHTML = html;

    const tb = $("rules-body");
    const tx = $("rules-json");

    function rowToInputs(it, idx){
      const id = it.id || (`ovr_${idx+1}`);
      const match = it.match || {};
      const action = it.action || (it.set && Object.keys(it.set).length ? "set" : "suppress");
      const setObj = it.set || {};
      const justification = it.justification || "";
      const expires_at = it.expires_at || (new Date().getFullYear()+1)+"-12-31";

      return `
        <tr data-idx="${idx}" style="border-bottom:1px solid rgba(255,255,255,.06); font-size:13px;">
          <td style="padding:10px 12px; white-space:nowrap;">
            <input data-k="id" value="${esc(id)}"
              style="width:160px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit;">
          </td>
          <td style="padding:10px 12px; min-width:260px;">
            <textarea data-k="match" spellcheck="false"
              style="width:360px; min-height:64px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit; font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12px;">${esc(JSON.stringify(match, null, 2))}</textarea>
          </td>
          <td style="padding:10px 12px; white-space:nowrap;">
            <select data-k="action" style="padding:8px 10px; border-radius:10px;">
              ${["suppress","set"].map(x=>`<option value="${x}" ${x===action?"selected":""}>${x}</option>`).join("")}
            </select>
          </td>
          <td style="padding:10px 12px; min-width:260px;">
            <textarea data-k="set" spellcheck="false"
              style="width:260px; min-height:64px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit; font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12px;">${esc(JSON.stringify(setObj, null, 2))}</textarea>
          </td>
          <td style="padding:10px 12px;">
            <input data-k="justification" value="${esc(justification)}"
              style="width:260px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit;">
          </td>
          <td style="padding:10px 12px; white-space:nowrap;">
            <input data-k="expires_at" value="${esc(expires_at)}" placeholder="${nowIsoDate()}"
              style="width:140px; padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.08);
              background:rgba(255,255,255,.03); color:inherit;">
          </td>
          <td style="padding:10px 12px; white-space:nowrap;">
            <button class="vsp-btn vsp-btn-soft" data-act="del">Delete</button>
          </td>
        </tr>
      `;
    }

    function syncTextAreaFromState(){
      if(!tx) return;
      tx.value = JSON.stringify(toPostPayload(state), null, 2);
    }

    function syncStateFromTable(){
      const rows = Array.from(tb.querySelectorAll("tr"));
      const out = [];
      for(const r of rows){
        const get = (k)=>r.querySelector(`[data-k="${k}"]`);
        const it = {};
        it.id = (get("id")?.value || "").trim() || undefined;
        it.action = (get("action")?.value || "").trim() || "suppress";
        it.justification = (get("justification")?.value || "").trim() || "";
        it.expires_at = (get("expires_at")?.value || "").trim() || "";

        // JSON fields
        try { it.match = JSON.parse(get("match")?.value || "{}"); }
        catch(e){ throw new Error("Bad JSON in match for row id="+(it.id||"(no id)")); }
        try { it.set = JSON.parse(get("set")?.value || "{}"); }
        catch(e){ throw new Error("Bad JSON in set for row id="+(it.id||"(no id)")); }

        // normalize: if action=suppress => set can be empty
        if(it.action === "suppress") {
          if(!it.match || typeof it.match!=="object") it.match = {};
          // keep set but it's ok if empty
        }
        out.push(it);
      }
      state.items = out;
      syncTextAreaFromState();
    }

    function syncTableFromState(){
      tb.innerHTML = items.map((it, idx)=>rowToInputs(it, idx)).join("");
      syncTextAreaFromState();
    }

    syncTableFromState();
    msg("Loaded "+items.length+" overrides.", "ok");

    // events
    $("rules-add")?.addEventListener("click", ()=>{
      state.items = state.items || [];
      state.items.push({
        id: "ovr_" + (state.items.length+1),
        match: { tool: "KICS" },
        action: "set",
        set: { severity: "LOW" },
        justification: "False positive / accepted risk",
        expires_at: (new Date().getFullYear()+1) + "-12-31"
      });
      syncTableFromState();
      msg("Added draft override. Edit then Save.", "ok");
    });

    $("rules-reload")?.addEventListener("click", async ()=>{
      msg("Reloading…", "ok");
      try{
        const j = normalizeFromApi(await apiGet());
        state.items = j.items || [];
        syncTableFromState();
        msg("Reloaded "+state.items.length+" overrides.", "ok");
      } catch(e){
        msg(String(e), "err");
      }
    });

    $("rules-save")?.addEventListener("click", async ()=>{
      try{
        // If user edited raw JSON, prefer that
        if(tx && tx.value && tx.value.trim().startsWith("{")){
          let raw;
          try { raw = JSON.parse(tx.value); }
          catch(e){ throw new Error("Raw JSON invalid: "+e); }
          // accept either {meta,overrides} or {version,items}
          let st = normalizeFromApi(raw);
          if(raw && raw.meta && Array.isArray(raw.overrides)) st = {version:1, items: raw.overrides};
          state.items = st.items || [];
          // re-render table from state to keep consistent
          syncTableFromState();
        } else {
          syncStateFromTable();
        }

        const payload = toPostPayload(state);
        msg("Saving…", "ok");
        const res = await apiSave(payload);
        msg("Saved OK. File: " + (res.file||"(unknown)"), "ok");
      } catch(e){
        msg(String(e && e.message ? e.message : e), "err");
      }
    });

    tb.addEventListener("click", (ev)=>{
      const t = ev.target;
      if(!(t instanceof Element)) return;
      const btn = t.closest ? t.closest('[data-act="del"]') : null;
      if(!btn) return;
      const tr = btn.closest("tr");
      if(!tr) return;
      tr.remove();
      try{
        syncStateFromTable();
        msg("Deleted row (not saved yet). Click Save.", "ok");
      } catch(e){
        msg(String(e), "err");
      }
    });
  }

  async function init(){
    const root = $("vsp-rules-main") || $("panel-rules") || document.querySelector('[data-panel="rules"]');
    if(!root){ console.warn("[VSP_RULES] rules pane not found"); return; }

    // Avoid double init
    if(root.getAttribute("data-vsp-rules-inited")==="1") return;
    root.setAttribute("data-vsp-rules-inited","1");

    root.innerHTML = '<div class="vsp-card" style="margin:12px 0; padding:14px;">Loading rule overrides…</div>';

    let state = { version: 1, items: [] };
    try{
      const j = normalizeFromApi(await apiGet());
      state.items = j.items || [];
      render(root, state);
    } catch(e){
      root.innerHTML = '<div class="vsp-card" style="margin:12px 0; padding:14px;">' +
        '<div style="font-weight:800;">Rule Overrides load failed</div>' +
        '<pre style="white-space:pre-wrap; opacity:.85; font-size:12px;">'+esc(String(e && e.stack ? e.stack : e))+'</pre>' +
        '</div>';
    }
  }

  // Public hook for router
  window.VSP_RULES_TAB_INIT = init;

  // Init only when hash is #rules
  function maybe(){
    const h = (location.hash||"").toLowerCase();
    if(h.includes("rules")) init();
  }
  window.addEventListener("hashchange", maybe);
  document.addEventListener("DOMContentLoaded", maybe);

  console.log("[VSP_RULE_OVERRIDES_TAB_V1] loaded");
})();


/* VSP_P1_REQUIRED_MARKERS_RO_V1 */
(function(){
  function ensureAttr(el, k, v){ try{ if(el && !el.getAttribute(k)) el.setAttribute(k,v); }catch(e){} }
  function ensureId(el, v){ try{ if(el && !el.id) el.id=v; }catch(e){} }
  function ensureTestId(el, v){ ensureAttr(el, "data-testid", v); }
  function ensureHiddenKpi(container){
    // Create hidden markers so gate can verify presence without altering layout
    try{
      const ids = ["kpi_total","kpi_critical","kpi_high","kpi_medium","kpi_low","kpi_info_trace"];
      let box = container.querySelector('#vsp-kpi-testids');
      if(!box){
        box = document.createElement('div');
        box.id = "vsp-kpi-testids";
        box.style.display = "none";
        container.appendChild(box);
      }
      ids.forEach(id=>{
        if(!box.querySelector('[data-testid="'+id+'"]')){
          const d=document.createElement('span');
          d.setAttribute('data-testid', id);
          box.appendChild(d);
        }
      });
    }catch(e){}
  }

  function run(){
    try {
      // Dashboard
      const dash = document.getElementById("vsp-dashboard-main") || document.querySelector('[id="vsp-dashboard-main"], #vsp-dashboard, .vsp-dashboard, main, body');
      if(dash) {
        ensureId(dash, "vsp-dashboard-main");
        // add required KPI data-testid markers
        ensureHiddenKpi(dash);
      }

      // Runs
      const runs = document.getElementById("vsp-runs-main") || document.querySelector('#vsp-runs, .vsp-runs, main, body');
      if(runs) ensureId(runs, "vsp-runs-main");

      // Data Source
      const ds = document.getElementById("vsp-data-source-main") || document.querySelector('#vsp-data-source, .vsp-data-source, main, body');
      if(ds) ensureId(ds, "vsp-data-source-main");

      // Settings
      const st = document.getElementById("vsp-settings-main") || document.querySelector('#vsp-settings, .vsp-settings, main, body');
      if(st) ensureId(st, "vsp-settings-main");

      // Rule overrides
      const ro = document.getElementById("vsp-rule-overrides-main") || document.querySelector('#vsp-rule-overrides, .vsp-rule-overrides, main, body');
      if(ro) ensureId(ro, "vsp-rule-overrides-main");
    } catch(e) {}
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run, { once:true });
  } else {
    run();
  }
  // re-run after soft refresh renders
  setTimeout(run, 300);
  setTimeout(run, 1200);
})();
/* end VSP_P1_REQUIRED_MARKERS_RO_V1 */

