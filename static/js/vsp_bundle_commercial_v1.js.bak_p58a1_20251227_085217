
// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = function(){ return document.visibilityState === "visible"; };
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.backoff = async function(fn, opt){
      opt = opt || {};
      let delay = opt.delay || 800;
      const maxDelay = opt.maxDelay || 8000;
      const maxTries = opt.maxTries || 6;
      for(let i=0;i<maxTries;i++){
        if(!window.__VSP_CIO.visible()){
          await window.__VSP_CIO.sleep(600);
          continue;
        }
        try { return await fn(); }
        catch(e){
          if(window.__VSP_CIO.debug) console.warn("[VSP] backoff retry", i+1, e);
          await window.__VSP_CIO.sleep(delay);
          delay = Math.min(maxDelay, delay*2);
        }
      }
      throw new Error("backoff_exhausted");
    };
    window.__VSP_CIO.api = {
      ridLatest: ()=>"/api/vsp/rid_latest_v3",
      runs: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gate: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsPage: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifact: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();


/* VSP_FETCH_DESCRIPTOR_SAFE_P0_V1 */
(function(){
  try{
    if (window.__vsp_fetch_descriptor_safe_p0_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_fetch_descriptor_safe_p0_v1 = true; }
    function canOverrideFetch(){
      try{
        const d = Object.getOwnPropertyDescriptor(window, "fetch");
        if (!d) return true;
        // if accessor exists, allow (setter may exist)
        if (d.get || d.set) return true;
        // data descriptor: must be writable OR configurable to redefine
        if (d.writable) return true;
        if (d.configurable) return true;
        return false;
      }catch(_){ return false; }
    }

    // Provide a helper for other wrappers to use
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_can_override_fetch = canOverrideFetch; }
    // If someone already wrapped fetch and locked it, don't crash future code.
    // We DO NOT wrap here; we only prevent TypeError by advising wrappers to check __vsp_can_override_fetch().
  }catch(_){}
})();

/* VSP_BUNDLE_COMMERCIAL_V1_STUB_P1_V1
   This file was broken (syntax error). Keep as safe stub that loads v2. */
(function(){
  try{
    if (window.__vsp_bundle_commercial_v1_stub) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_bundle_commercial_v1_stub = true; }
    var s=document.createElement("script");
    s.src="/static/js/vsp_bundle_commercial_v2.js";
    s.defer=true;
    (document.head||document.documentElement).appendChild(s);
    console.warn("[VSP] v1 bundle stub loaded -> redirected to v2");
  }catch(e){}
})();



/* =======================
   VSP_P1_TABS3_UI_V1
   Data Source + Settings + Rule Overrides
   ======================= */
(() => {
  if (window.__vsp_p1_tabs3_ui_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_p1_tabs3_ui_v1 = true; }
  const $ = (sel, root=document) => root.querySelector(sel);
  const esc = (s) => (s==null?'':String(s)).replace(/[&<>"']/g, (c)=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));

  function ensureStyle(){
    if (document.getElementById("vsp_tabs3_style_v1")) return;
    const st = document.createElement("style");
    st.id = "vsp_tabs3_style_v1";
    st.textContent = `
      .vsp-card{background:#0f1b2d;border:1px solid rgba(148,163,184,.18);border-radius:14px;padding:14px}
      .vsp-row{display:flex;gap:12px;flex-wrap:wrap}
      .vsp-kpi{min-width:180px}
      .vsp-muted{color:#94a3b8}
      .vsp-btn{background:#111c30;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:8px 10px;cursor:pointer}
      .vsp-btn:hover{border-color:rgba(148,163,184,.45)}
      .vsp-in{background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:8px 10px;outline:none}
      .vsp-in:focus{border-color:rgba(59,130,246,.55)}
      table.vsp-t{width:100%;border-collapse:separate;border-spacing:0 8px}
      table.vsp-t th{font-weight:600;text-align:left;color:#cbd5e1;font-size:12px;padding:0 10px}
      table.vsp-t td{background:#0b1324;border-top:1px solid rgba(148,163,184,.18);border-bottom:1px solid rgba(148,163,184,.18);padding:10px;font-size:13px;vertical-align:top}
      table.vsp-t tr td:first-child{border-left:1px solid rgba(148,163,184,.18);border-top-left-radius:12px;border-bottom-left-radius:12px}
      table.vsp-t tr td:last-child{border-right:1px solid rgba(148,163,184,.18);border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-badge{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(148,163,184,.22);font-size:12px}
      .vsp-pager{display:flex;gap:10px;align-items:center;justify-content:flex-end;margin-top:10px}
      .vsp-code{width:100%;min-height:280px;resize:vertical;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:12px;padding:12px}
      .vsp-ok{color:#86efac}
      .vsp-err{color:#fca5a5}
    `;
    document.head.appendChild(st);
  }

  async function apiJson(url, opt){
    const r = await fetch(url, opt);
    const t = await r.text();
    let j = null;
    try{ j = JSON.parse(t); }catch(_e){ j = { ok:false, err:"non-json", raw:t.slice(0,800) }; }
    if (!r.ok) throw Object.assign(new Error("HTTP "+r.status), {status:r.status, body:j});
    return j;
  }

  function mount(){
    return $("#vsp_tab_root") || document.body;
  }
  function tabName(){
    return (window.__vsp_tab || ($("#vsp_tab_root")?.getAttribute("data-vsp-tab")) || "").trim();
  }

  // ---------------- Data Source ----------------
  function renderCounts(counts){
    const keys = ["TOTAL","CRITICAL","HIGH","MEDIUM","LOW","INFO", "TRACE"];
    return keys.map(k=>{
      const v = counts?.[k] ?? 0;
      return `<div class="vsp-card vsp-kpi"><div class="vsp-muted" style="font-size:12px">${k}</div><div style="font-size:22px;font-weight:700;margin-top:6px">${v}</div></div>`;
    }).join("");
  }

  async function renderDataSource(){
    ensureStyle();
    const root = mount();
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;align-items:center;margin-bottom:12px">
        <div>
          <div style="font-size:18px;font-weight:800">Data Source</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Table view of  (latest run) with filters & paging</div>
        </div>
        <div class="vsp-row" style="gap:8px">
          <button class="vsp-btn" id="ds_refresh">Refresh</button>
          <button class="vsp-btn" id="ds_dl_json">Download JSON</button>
        </div>
      </div>

      <div class="vsp-row" id="ds_kpis" style="margin-bottom:12px"></div>

      <div class="vsp-card" style="margin-bottom:12px">
        <div class="vsp-row" style="align-items:center">
          <input class="vsp-in" id="ds_q" placeholder="search (tool, rule_id, message, file, cwe)..." style="min-width:260px;flex:1"/>
          <select class="vsp-in" id="ds_sev">
            <option value="">All severities</option>
            <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option>
          </select>
          <input class="vsp-in" id="ds_tool" placeholder="tool (exact, e.g. semgrep)" style="min-width:200px"/>
          <select class="vsp-in" id="ds_limit">
            <option value="10">10 / page</option>
            <option value="20" selected>20 / page</option>
            <option value="50">50 / page</option>
          </select>
        </div>
        <div class="vsp-muted" id="ds_meta" style="margin-top:10px;font-size:12px"></div>
      </div>

      <div class="vsp-card">
        <table class="vsp-t">
          <thead>
            <tr>
              <th>Severity</th><th>Tool</th><th>Rule</th><th>File</th><th>Line</th><th>Message</th>
            </tr>
          </thead>
          <tbody id="ds_tbody"></tbody>
        </table>
        <div class="vsp-pager">
          <button class="vsp-btn" id="ds_prev">Prev</button>
          <div class="vsp-muted" id="ds_page">Page 1/1</div>
          <button class="vsp-btn" id="ds_next">Next</button>
        </div>
      </div>
    `;

    let state = { offset:0, limit:20, total:0, last:null };

    const qEl = $("#ds_q"), sevEl=$("#ds_sev"), toolEl=$("#ds_tool"), limEl=$("#ds_limit");
    const kpis = $("#ds_kpis"), tbody=$("#ds_tbody"), meta=$("#ds_meta"), page=$("#ds_page");

    async function load(){
      const q = (qEl.value||"").trim();
      const severity = (sevEl.value||"").trim();
      const tool = (toolEl.value||"").trim();
      const limit = parseInt(limEl.value||"20",10) || 20;
      state.limit = limit;

      const url = `/api/vsp/findings_v1?limit=${encodeURIComponent(limit)}&offset=${encodeURIComponent(state.offset)}&q=${encodeURIComponent(q)}&severity=${encodeURIComponent(severity)}&tool=${encodeURIComponent(tool.toLowerCase())}`;
      const j = await apiJson(url);
      state.total = j.total||0;
      state.last = j;
      kpis.innerHTML = renderCounts(j.counts||{});
      meta.innerHTML = `run_dir: <span class="vsp-muted">${esc(j.run_dir||"")}</span> · total_filtered: <b>${esc(j.total||0)}</b> · limit=${esc(j.limit)} offset=${esc(j.offset)}`;

      const items = j.items||[];
      tbody.innerHTML = items.map(it=>{
        const sev = esc(it.severity||"");
        const tool = esc(it.tool||"");
        const rule = esc(it.rule_id||"");
        const file = esc(it.file||"");
        const line = esc(it.line||"");
        const msg  = esc(it.message||"");
        return `<tr>
          <td><span class="vsp-badge">${sev}</span></td>
          <td>${tool}</td>
          <td>${rule}</td>
          <td style="max-width:360px;word-break:break-word">${file}</td>
          <td>${line}</td>
          <td style="max-width:520px;word-break:break-word">${msg}</td>
        </tr>`;
      }).join("");

      const pages = Math.max(1, Math.ceil((state.total||0)/state.limit));
      const cur = Math.min(pages, Math.floor((state.offset||0)/state.limit)+1);
      page.textContent = `Page ${cur}/${pages}`;
      $("#ds_prev").disabled = (state.offset<=0);
      $("#ds_next").disabled = (state.offset + state.limit >= state.total);
    }

    function debounce(fn, ms=250){
      let t=null;
      return ()=>{ clearTimeout(t); t=setTimeout(fn, ms); };
    }
    const reloadDebounced = debounce(()=>{ state.offset=0; load().catch(e=>console.error(e)); }, 250);

    qEl.addEventListener("input", reloadDebounced);
    sevEl.addEventListener("change", ()=>{ state.offset=0; load().catch(console.error); });
    toolEl.addEventListener("input", reloadDebounced);
    limEl.addEventListener("change", ()=>{ state.offset=0; load().catch(console.error); });

    $("#ds_refresh").onclick = ()=>{ load().catch(console.error); };
    $("#ds_prev").onclick = ()=>{ state.offset = Math.max(0, state.offset - state.limit); load().catch(console.error); };
    $("#ds_next").onclick = ()=>{ state.offset = state.offset + state.limit; load().catch(console.error); };

    $("#ds_dl_json").onclick = ()=>{
      const data = state.last || {};
      const blob = new Blob([JSON.stringify(data, null, 2)], {type:"application/json"});
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "vsp_findings_v1.json";
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 1200);
    };

    await load();
  }

  // ---------------- Settings ----------------
  async function renderSettings(){
    ensureStyle();
    const root = mount();
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;align-items:center;margin-bottom:12px">
        <div>
          <div style="font-size:18px;font-weight:800">Settings</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Commercial-friendly config JSON (GET/POST)</div>
        </div>
        <div class="vsp-row" style="gap:8px">
          <button class="vsp-btn" id="st_reload">Reload</button>
          <button class="vsp-btn" id="st_save">Save</button>
          <button class="vsp-btn" id="st_dl">Download</button>
        </div>
      </div>

      <div class="vsp-row" style="margin-bottom:12px">
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Environment</div>
          <pre id="st_env" style="white-space:pre-wrap;margin:10px 0 0 0;font-size:12px;color:#cbd5e1"></pre>
        </div>
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Storage</div>
          <div id="st_path" class="vsp-muted" style="margin-top:10px;font-size:12px"></div>
          <div id="st_msg" style="margin-top:10px;font-size:12px"></div>
        </div>
      </div>

      <div class="vsp-card">
        <div class="vsp-muted" style="font-size:12px;margin-bottom:8px">settings.json</div>
        <textarea id="st_text" class="vsp-code" spellcheck="false"></textarea>
      </div>
    `;

    const envEl = $("#st_env"), pathEl=$("#st_path"), msgEl=$("#st_msg"), txt=$("#st_text");

    async function load(){
      msgEl.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await apiJson("/api/vsp/settings_v1");
      envEl.textContent = JSON.stringify(j.env||{}, null, 2);
      pathEl.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.settings||{}, null, 2);
      msgEl.innerHTML = `<span class="vsp-ok">OK</span> · ts=${esc(j.ts||"")}`;
      return j;
    }

    async function save(){
      let obj = {};
      try { obj = JSON.parse(txt.value||"{}"); }
      catch(e){ msgEl.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msgEl.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await apiJson("/api/vsp/settings_v1", {
        method:"POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify({settings: obj})
      });
      msgEl.innerHTML = `<span class="vsp-ok">Saved</span> · ${esc(j.path||"")}`;
      return j;
    }

    $("#st_reload").onclick = ()=>load().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#st_save").onclick = ()=>save().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#st_dl").onclick = ()=>{
      const blob = new Blob([txt.value||"{}"], {type:"application/json"});
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "vsp_settings.json";
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 1200);
    };

    await load();
  }

  // ---------------- Rule Overrides ----------------
  async function renderRuleOverrides(){
    ensureStyle();
    const root = mount();
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;align-items:center;margin-bottom:12px">
        <div>
          <div style="font-size:18px;font-weight:800">Rule Overrides</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Manage custom overrides (GET/POST) · stored under ui/out_ci/rule_overrides_v1/rules.json</div>
        </div>
        <div class="vsp-row" style="gap:8px">
          <button class="vsp-btn" id="ro_reload">Reload</button>
          <button class="vsp-btn" id="ro_validate">Validate</button>
          <button class="vsp-btn" id="ro_save">Save</button>
          <button class="vsp-btn" id="ro_dl">Download</button>
        </div>
      </div>

      <div class="vsp-row" style="margin-bottom:12px">
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Quick Schema</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:8px;line-height:1.5">
            Each rule: {"id","tool","rule_id","action","severity","reason","expires"}<br/>
            action examples: "ignore" | "downgrade" | "upgrade"<br/>
            severity override: CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE
          </div>
        </div>
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Status</div>
          <div id="ro_path" class="vsp-muted" style="margin-top:10px;font-size:12px"></div>
          <div id="ro_msg" style="margin-top:10px;font-size:12px"></div>
        </div>
      </div>

      <div class="vsp-card">
        <div class="vsp-muted" style="font-size:12px;margin-bottom:8px">rules.json</div>
        <textarea id="ro_text" class="vsp-code" spellcheck="false"></textarea>
      </div>
    `;

    const pathEl=$("#ro_path"), msgEl=$("#ro_msg"), txt=$("#ro_text");

    function normalize(obj){
      // accept list or {rules:[...]}
      if (Array.isArray(obj)) obj = {rules: obj};
      if (!obj || typeof obj !== "object") throw new Error("Root must be object or array");
      if (!Array.isArray(obj.rules)) obj.rules = [];
      // ensure objects
      obj.rules = obj.rules.filter(x=>x && typeof x==="object" && !Array.isArray(x));
      return obj;
    }

    async function load(){
      msgEl.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await apiJson("/api/vsp/rule_overrides_v1");
      pathEl.textContent = `path: ${j.path||""}`;
      const data = j.data || {rules:[]};
      txt.value = JSON.stringify(data, null, 2);
      msgEl.innerHTML = `<span class="vsp-ok">OK</span> · rules=${esc((data.rules||[]).length)} · ts=${esc(j.ts||"")}`;
    }

    function validate(){
      let obj;
      try { obj = JSON.parse(txt.value||"{}"); obj = normalize(obj); }
      catch(e){ msgEl.innerHTML = `<span class="vsp-err">Invalid:</span> ${esc(e.message||String(e))}`; return null; }
      // light validation
      for (const r of obj.rules){
        if (!("tool" in r) || !("rule_id" in r)){
          msgEl.innerHTML = `<span class="vsp-err">Invalid rule:</span> each rule needs tool + rule_id`; return null;
        }
      }
      msgEl.innerHTML = `<span class="vsp-ok">Valid</span> · rules=${esc(obj.rules.length)}`;
      return obj;
    }

    async function save(){
      const obj = validate();
      if (!obj) return;
      msgEl.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await apiJson("/api/vsp/rule_overrides_v1", {
        method:"POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify({data: obj})
      });
      msgEl.innerHTML = `<span class="vsp-ok">Saved</span> · rules_n=${esc(j.rules_n||"")} · ts=${esc(j.ts||"")}`;
      await sleep(150);
      await load();
    }

    $("#ro_reload").onclick = ()=>load().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#ro_validate").onclick = ()=>validate();
    $("#ro_save").onclick = ()=>save().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#ro_dl").onclick = ()=>{
      const blob = new Blob([txt.value||"{}"], {type:"application/json"});
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "vsp_rule_overrides.json";
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 1200);
    };

    await load();
  }

  // --------------- Router ---------------
  async function boot(){
    const t = tabName() || location.pathname.replace(/^\//,'');
    try{
      if (t.includes("data_source")) return await renderDataSource();
      if (t.includes("settings")) return await renderSettings();
      if (t.includes("rule_overrides")) return await renderRuleOverrides();
    }catch(e){
      console.error(e);
      const root = mount();
      root.innerHTML = `<div class="vsp-card"><div style="font-weight:800">Tab render failed</div><pre style="white-space:pre-wrap;margin-top:10px" class="vsp-muted">${esc(e.message||String(e))}</pre></div>`;
    }
  }

  document.addEventListener("DOMContentLoaded", boot);
})();



/* VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1 (auto refresh Runs + DataSource after Apply Rule Overrides) */
(()=> {
  try{
    if (window.__vsp_p1_rule_overrides_autorefresh_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_p1_rule_overrides_autorefresh_v1 = true; }
    const EVT = "vsp:rule_overrides_applied";
    const isRuleUrl = (u)=> {
      u = String(u||"");
      return /\/api\/ui\/rule_overrides/i.test(u) || /\/api\/vsp\/rule_overrides/i.test(u);
    };

    function safeReload(){
      try{ location.reload(); }catch(_){}
    }

    function afterApply(detail){
      try{
        const path = (location && location.pathname) ? String(location.pathname) : "";
        // Prefer calling known refresh hooks if present
        if (typeof window.refreshRuns === "function") { try{ window.refreshRuns(); }catch(_){ safeReload(); } return; }
        if (typeof window.refreshCounts === "function") { try{ window.refreshCounts(); }catch(_){ /* ignore */ } }

        // Data source pagination hook (we patch it to expose __vsp_ds_reload_v1)
        if (typeof window.__vsp_ds_reload_v1 === "function") { try{ window.__vsp_ds_reload_v1(); }catch(_){ /* fallback below */ } }

        // last resort: reload page if on runs/data_source
        if (/\/runs\b/i.test(path) || /\/data_source\b/i.test(path)) safeReload();
      }catch(_){}
    }

    window.addEventListener(EVT, (e)=> {
      afterApply((e && e.detail) || {});
    });

    // Wrap fetch once: detect successful Apply calls then dispatch event
    const origFetch = window.fetch;
    if (typeof origFetch === "function" && !origFetch.__vsp_p1_rule_overrides_autorefresh_v1){
      window.fetch = async function(input, init){
        const url = (typeof input === "string") ? input : (input && input.url) || "";
        const method = (init && init.method) ? String(init.method).toUpperCase() : "GET";

        const resp = await origFetch(input, init);

        try{
          if (url && isRuleUrl(url) && method !== "GET"){
            const clone = resp.clone();
            let j = null;
            try{ j = await clone.json(); }catch(_){ j = null; }

            const ok = !!(j && (j.ok === true || j.ok === true || j.status === "ok" || j.result === "ok"));
            if (resp.ok && ok){
              const detail = { url, method, ts: Date.now(), payload: j };
              try{ window.dispatchEvent(new CustomEvent(EVT, { detail })); }catch(_){}
              // also run locally immediately
              setTimeout(()=> afterApply(detail), 30);
            }
          }
        }catch(_){}

        return resp;
      };
      window.fetch.__vsp_p1_rule_overrides_autorefresh_v1 = true;
    }
  }catch(e){
    console && console.warn && console.warn("VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1 failed:", e);
  }
})();

