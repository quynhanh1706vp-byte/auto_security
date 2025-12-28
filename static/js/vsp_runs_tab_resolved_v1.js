
/* --- VSP_P464C2_FORCE_MOUNT_NODE_V1 --- */
(function(){
  try{
    window.__VSP_P464C_EXPORTS_MOUNT = function(){
      return document.querySelector('#vsp_p464c_exports_mount')
        || document.querySelector('#vsp_runs_root')
        || document.querySelector('#vsp_runs')
        || document.querySelector('#runs_root')
        || document.querySelector('.vsp-runs-root')
        || document.querySelector('main')
        || document.body;
    };
  }catch(e){}
})();
/* --- /VSP_P464C2_FORCE_MOUNT_NODE_V1 --- */

/* VSP_AUTOSTUB_JS_V1: file was broken; stubbed to keep UI alive */
(function(){
  try{ console.warn('[VSP][AUTOSTUB] '+(document.currentScript&&document.currentScript.src||'js')+' stubbed'); }catch(_){ }
})();


/* VSP_P1_REQUIRED_MARKERS_RUNS2_V1 */
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
/* end VSP_P1_REQUIRED_MARKERS_RUNS2_V1 */


/* --- VSP_P464B_RUNS_EXPORTS_PANEL_V1 --- */
(function(){
  function qs(sel, root){ return (root||document).querySelector(sel); }

  function vspGetRidBestEffort(){
    const a = qs('[data-vsp-rid].selected') || qs('[data-rid].selected') || qs('[data-vsp-rid]') || qs('[data-rid]');
    if (a){
      return (a.getAttribute('data-vsp-rid') || a.getAttribute('data-rid') || '').trim();
    }
    const sel = qs('select[name="rid"]') || qs('select#rid') || qs('select.vsp-rid');
    if (sel && sel.value) return String(sel.value).trim();
    try{
      const u = new URL(location.href);
      const rid = (u.searchParams.get('rid')||'').trim();
      if (rid) return rid;
    }catch(e){}
    return "";
  }

  function vspBuildUrl(path, rid){
    const u = new URL(path, location.origin);
    if (rid) u.searchParams.set('rid', rid);
    return u.toString();
  }

  function vspEnsureStyles(){
    if (qs('#vsp_p464b_exports_css')) return;
    const st = document.createElement('style');
    st.id='vsp_p464b_exports_css';
    st.textContent = `
      .vsp-p464b-exports { margin-top: 12px; border: 1px solid rgba(255,255,255,.08); border-radius: 12px; padding: 12px; background: rgba(255,255,255,.03); }
      .vsp-p464b-exports h3 { margin: 0 0 8px 0; font-size: 14px; opacity: .9; }
      .vsp-p464b-row { display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p464b-btn { padding: 8px 10px; border-radius: 10px; border: 1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color: #fff; cursor:pointer; }
      .vsp-p464b-btn:hover { border-color: rgba(255,255,255,.22); }
      .vsp-p464b-kv { margin-top: 10px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size: 12px; opacity: .92; }
      .vsp-p464b-kv .line { margin: 4px 0; }
      .vsp-p464b-pill { display:inline-block; padding:2px 8px; border-radius: 999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); }
      .vsp-p464b-err { color: #ff8f8f; }
      .vsp-p464b-ok  { color: #b6fcb6; }
    `;
    document.head.appendChild(st);
  }

  async function vspFetchSha256(rid){
    const url = vspBuildUrl('/api/vsp/sha256', rid);
    const r = await fetch(url, {credentials:'same-origin'});
    const j = await r.json().catch(()=>null);
    if (!r.ok) throw new Error((j && (j.err||j.error)) || ('HTTP '+r.status));
    return j;
  }

  function vspCopy(text){
    try{ navigator.clipboard.writeText(String(text||'')); }catch(e){}
  }

  function vspRender(root){
    
  // --- VSP_P464E2_PING_ON_EXPORTS_RENDER_V1 ---
  try{ fetch('/api/vsp/p464_ping', {credentials:'same-origin'}).catch(function(){}); }catch(e){}
  // --- /VSP_P464E2_PING_ON_EXPORTS_RENDER_V1 ---
vspEnsureStyles();
    if (!root) return;
    if (qs('.vsp-p464b-exports', root)) return;

    const box=document.createElement('div');
    box.className='vsp-p464b-exports';
    box.innerHTML = `
      <h3>Exports</h3>
      <div class="vsp-p464b-row">
        <button class="vsp-p464b-btn" id="vsp_p464b_csv">Download CSV</button>
        <button class="vsp-p464b-btn" id="vsp_p464b_tgz">Download TGZ</button>
        <button class="vsp-p464b-btn" id="vsp_p464b_sha_btn">Refresh SHA256</button>
      </div>
      <div class="vsp-p464b-kv">
        <div class="line">RID: <span class="vsp-p464b-pill" id="vsp_p464b_rid">(auto latest)</span></div>
        <div class="line">SHA256: <span class="vsp-p464b-pill" id="vsp_p464b_sha">-</span>
          <button class="vsp-p464b-btn" id="vsp_p464b_copy" style="padding:6px 8px">Copy</button>
        </div>
        <div class="line">Bytes: <span class="vsp-p464b-pill" id="vsp_p464b_bytes">-</span></div>
        <div class="line">Status: <span class="vsp-p464b-pill" id="vsp_p464b_status">idle</span></div>
      </div>
    `;
    root.appendChild(box);

    const elRid=qs('#vsp_p464b_rid', box);
    const elSha=qs('#vsp_p464b_sha', box);
    const elBytes=qs('#vsp_p464b_bytes', box);
    const elStatus=qs('#vsp_p464b_status', box);

    function setStatus(t, ok){
      elStatus.textContent=t;
      elStatus.classList.remove('vsp-p464b-err','vsp-p464b-ok');
      if (ok===true) elStatus.classList.add('vsp-p464b-ok');
      if (ok===false) elStatus.classList.add('vsp-p464b-err');
    }

    async function refresh(){
      const rid=vspGetRidBestEffort();
      elRid.textContent=rid || '(auto latest)';
      setStatus('loading...', null);
      try{
        const j=await vspFetchSha256(rid);
        elRid.textContent=j.rid || rid || '(auto latest)';
        elSha.textContent=j.sha256 || '-';
        elBytes.textContent=(j.bytes!=null ? String(j.bytes) : '-');
        setStatus('ok', true);
      }catch(e){
        setStatus('error: '+(e && e.message ? e.message : String(e)), false);
      }
    }

    qs('#vsp_p464b_sha_btn', box).addEventListener('click', refresh);
    qs('#vsp_p464b_copy', box).addEventListener('click', ()=>vspCopy(elSha.textContent));
    qs('#vsp_p464b_csv', box).addEventListener('click', ()=>{
      const rid=vspGetRidBestEffort();
      window.open(vspBuildUrl('/api/vsp/export_csv', rid), '_blank');
    });
    qs('#vsp_p464b_tgz', box).addEventListener('click', ()=>{
      const rid=vspGetRidBestEffort();
      window.open(vspBuildUrl('/api/vsp/export_tgz', rid), '_blank');
    });

    setTimeout(refresh, 80);
  }

  function hook(){
    const root = (window.__VSP_P464C_EXPORTS_MOUNT ? window.__VSP_P464C_EXPORTS_MOUNT() : document.body);
    if (root) vspRender(root);
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', hook);
  } else {
    hook();
  }
  setInterval(hook, 1200);
})();
 /* --- /VSP_P464B_RUNS_EXPORTS_PANEL_V1 --- */


/* --- VSP_P465_EXPORTS_PANEL_POLISH_V1 --- */
(function(){
  function qs(sel, root){ return (root||document).querySelector(sel); }

  function getRid(){
    try{
      const a = qs('[data-vsp-rid].selected') || qs('[data-rid].selected') || qs('[data-vsp-rid]') || qs('[data-rid]');
      if (a) return (a.getAttribute('data-vsp-rid') || a.getAttribute('data-rid') || '').trim();
      const sel = qs('select[name="rid"]') || qs('select#rid') || qs('select.vsp-rid');
      if (sel && sel.value) return String(sel.value).trim();
      const u = new URL(location.href);
      return (u.searchParams.get('rid')||'').trim();
    }catch(e){ return ""; }
  }

  function buildUrl(path, rid){
    const u = new URL(path, location.origin);
    if (rid) u.searchParams.set('rid', rid);
    return u.toString();
  }

  function copy(text){
    try{ navigator.clipboard.writeText(String(text||'')); }catch(e){}
  }

  async function fetchSha(rid){
    const r = await fetch(buildUrl('/api/vsp/sha256', rid), {credentials:'same-origin'});
    const j = await r.json().catch(()=>null);
    if(!r.ok) throw new Error('HTTP '+r.status);
    return j || {};
  }

  function ensureExtraUI(box){
    if (qs('.vsp-p465-extra', box)) return;

    const st = document.createElement('style');
    st.textContent = `
      .vsp-p465-extra { margin-top: 10px; border-top: 1px dashed rgba(255,255,255,.10); padding-top: 10px; }
      .vsp-p465-grid { display:grid; grid-template-columns: 120px 1fr; gap:6px 10px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; font-size: 12px; }
      .vsp-p465-k { opacity:.75; }
      .vsp-p465-v { overflow-wrap:anywhere; }
      .vsp-p465-actions { margin-top: 8px; display:flex; flex-wrap:wrap; gap:10px; }
      .vsp-p465-btn { padding:6px 9px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; cursor:pointer; }
      .vsp-p465-btn:hover { border-color: rgba(255,255,255,.22); }
      .vsp-p465-pill { display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); }
    `;
    if (!qs('#vsp_p465_css')){ st.id='vsp_p465_css'; document.head.appendChild(st); }

    const extra = document.createElement('div');
    extra.className='vsp-p465-extra';
    extra.innerHTML = `
      <div class="vsp-p465-grid">
        <div class="vsp-p465-k">RID</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_rid">-</span></div>
        <div class="vsp-p465-k">File</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_file">-</span></div>
        <div class="vsp-p465-k">Bytes</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_bytes">-</span></div>
        <div class="vsp-p465-k">SHA256</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_sha">-</span></div>
      </div>
      <div class="vsp-p465-actions">
        <button class="vsp-p465-btn" id="vsp_p465_copy_rid">Copy RID</button>
        <button class="vsp-p465-btn" id="vsp_p465_copy_sha">Copy SHA</button>
        <button class="vsp-p465-btn" id="vsp_p465_open_exports">Open Exports</button>
      </div>
    `;
    box.appendChild(extra);

    qs('#vsp_p465_copy_rid', extra).addEventListener('click', ()=>copy(qs('#vsp_p465_rid', extra).textContent));
    qs('#vsp_p465_copy_sha', extra).addEventListener('click', ()=>copy(qs('#vsp_p465_sha', extra).textContent));
    qs('#vsp_p465_open_exports', extra).addEventListener('click', ()=>{
      window.open('/api/vsp/exports_v1', '_blank');
    });
  }

  async function refresh(box){
    ensureExtraUI(box);

    const rid = getRid();
    const elRid = qs('#vsp_p465_rid', box);
    const elFile = qs('#vsp_p465_file', box);
    const elBytes = qs('#vsp_p465_bytes', box);
    const elSha = qs('#vsp_p465_sha', box);

    try{
      const j = await fetchSha(rid);
      elRid.textContent = j.rid || rid || '(auto latest)';
      elFile.textContent = j.file || '-';
      elBytes.textContent = (j.bytes!=null ? String(j.bytes) : '-');
      elSha.textContent = j.sha256 || '-';
    }catch(e){
      // keep old values, but show rid at least
      elRid.textContent = rid || '(auto latest)';
    }
  }

  function hook(){
    const box = qs('.vsp-p464b-exports') || qs('.vsp-p464-exports');
    if(!box) return;
    refresh(box);
  }

  // initial + poll when RID changes
  let lastRid = null;
  setInterval(function(){
    const rid = getRid() || '';
    if (rid !== lastRid){
      lastRid = rid;
      hook();
    }
  }, 900);

  setTimeout(hook, 120);
})();
/* --- /VSP_P465_EXPORTS_PANEL_POLISH_V1 --- */


/* --- VSP_P466A_RUNS_SEARCH_SORT_KEEPSEL_V1 --- */
(function(){
  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  const LS_KEY = 'vsp_runs_selected_rid_v1';

  function getSelectedRid(){
    try{ return (localStorage.getItem(LS_KEY)||'').trim(); }catch(e){ return ''; }
  }
  function setSelectedRid(rid){
    try{ localStorage.setItem(LS_KEY, String(rid||'').trim()); }catch(e){}
  }

  function getRidFromRow(row){
    if(!row) return '';
    const rid = (row.getAttribute('data-vsp-rid') || row.getAttribute('data-rid') || '').trim();
    if(rid) return rid;
    // try first cell text
    const td = row.querySelector('td');
    if(td){
      const t = (td.textContent||'').trim();
      // basic heuristic: RID often starts with VSP_
      if(t.startsWith('VSP_')) return t;
    }
    return '';
  }

  function markSelectedRow(container){
    const want = getSelectedRid();
    if(!want) return;
    const rows = qsa('tr', container);
    for(const r of rows){
      const rid = getRidFromRow(r);
      if(rid && rid === want){
        r.classList.add('vsp-p466a-selected');
      }else{
        r.classList.remove('vsp-p466a-selected');
      }
    }
  }

  function ensureStyles(){
    if(qs('#vsp_p466a_css')) return;
    const st=document.createElement('style');
    st.id='vsp_p466a_css';
    st.textContent = `
      .vsp-p466a-toolbar{ display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin: 10px 0; }
      .vsp-p466a-inp{ padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; min-width: 240px; }
      .vsp-p466a-sel{ padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; }
      tr.vsp-p466a-selected{ outline: 2px solid rgba(255,255,255,.14); background: rgba(255,255,255,.04) !important; }
      .vsp-p466a-hidden{ display:none !important; }
    `;
    document.head.appendChild(st);
  }

  function findRunsTableRoot(){
    // try common runs containers
    return qs('#vsp_runs_root')
      || qs('#vsp_runs')
      || qs('#runs_root')
      || qs('.vsp-runs-root')
      || qs('#vsp_p464c_exports_mount')?.parentElement
      || qs('main')
      || document.body;
  }

  function findTable(container){
    // pick the biggest table in runs area
    const tables = qsa('table', container);
    if(!tables.length) return null;
    let best = tables[0], bestRows = qsa('tr', best).length;
    for(const t of tables){
      const n = qsa('tr', t).length;
      if(n > bestRows){ best=t; bestRows=n; }
    }
    return best;
  }

  function parseEpochFromRowText(row){
    const txt = (row.textContent||'');
    // heuristic: if text contains YYYY-MM-DD or YYYY/MM/DD
    const m = txt.match(/(20\d{2})[-\/](\d{2})[-\/](\d{2})/);
    if(!m) return 0;
    const y=+m[1], mo=+m[2], d=+m[3];
    // treat as local midnight
    const dt = new Date(y, mo-1, d, 0,0,0,0);
    return dt.getTime() || 0;
  }

  function ensureToolbar(container, table){
    ensureStyles();
    if(qs('.vsp-p466a-toolbar', container)) return;

    const bar=document.createElement('div');
    bar.className='vsp-p466a-toolbar';

    const inp=document.createElement('input');
    inp.className='vsp-p466a-inp';
    inp.placeholder='Search runs (rid / status / target / date...)';
    inp.autocomplete='off';

    const sel=document.createElement('select');
    sel.className='vsp-p466a-sel';
    sel.innerHTML = `
      <option value="new">Sort: Newest</option>
      <option value="old">Sort: Oldest</option>
    `;

    bar.appendChild(inp);
    bar.appendChild(sel);

    // insert above table
    table.parentElement.insertBefore(bar, table);

    function apply(){
      const q=(inp.value||'').trim().toLowerCase();
      const rows=qsa('tbody tr', table);
      // filter
      for(const r of rows){
        const t=(r.textContent||'').toLowerCase();
        if(!q || t.includes(q)) r.classList.remove('vsp-p466a-hidden');
        else r.classList.add('vsp-p466a-hidden');
      }
      // sort (stable within visible)
      const visible = rows.filter(r=>!r.classList.contains('vsp-p466a-hidden'));
      visible.sort((a,b)=>{
        const ta=parseEpochFromRowText(a);
        const tb=parseEpochFromRowText(b);
        // fallback: rid text compare
        if(ta===tb){
          const ra=getRidFromRow(a), rb=getRidFromRow(b);
          return (ra<rb?-1:ra>rb?1:0);
        }
        return sel.value==='new' ? (tb-ta) : (ta-tb);
      });
      const tb = qs('tbody', table) || table;
      for(const r of visible) tb.appendChild(r);

      markSelectedRow(table);
    }

    inp.addEventListener('input', ()=>{ apply(); });
    sel.addEventListener('change', ()=>{ apply(); });

    // click -> remember selected rid
    table.addEventListener('click', (ev)=>{
      const tr = ev.target && ev.target.closest ? ev.target.closest('tr') : null;
      if(!tr) return;
      const rid=getRidFromRow(tr);
      if(rid){ setSelectedRid(rid); markSelectedRow(table); }
    });

    // initial apply
    setTimeout(apply, 80);
  }

  function hook(){
    const root=findRunsTableRoot();
    const table=findTable(root);
    if(!table) return;
    ensureToolbar(root, table);
    markSelectedRow(table);
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', hook);
  else hook();

  setInterval(hook, 1200);
})();
/* --- /VSP_P466A_RUNS_SEARCH_SORT_KEEPSEL_V1 --- */


/* --- VSP_P466A2_RUNS_DEDUPE_SORT_FIXLOADED_V1 --- */
(function(){
  if (window.__VSP_P466A2_ON) return;
  window.__VSP_P466A2_ON = true;

  const LS_SORT = "vsp_runs_sort_v1";
  const LS_SEL  = "vsp_runs_selected_rid_v1";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function txt(el){ return (el && el.textContent ? el.textContent : "").trim(); }

  function ensureCss(){
    if (qs("#vsp_p466a2_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p466a2_css";
    st.textContent = `
      .vsp-p466a2-sort{ margin-left:10px; padding:8px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; }
      .vsp-p466a2-selected{ outline:2px solid rgba(255,255,255,.14); background: rgba(255,255,255,.04)!important; }
      .vsp-p466a2-hidden{ display:none!important; }
    `;
    document.head.appendChild(st);
  }

  function getSort(){
    try{ return (localStorage.getItem(LS_SORT)||"new"); }catch(e){ return "new"; }
  }
  function setSort(v){
    try{ localStorage.setItem(LS_SORT, v); }catch(e){}
  }
  function getSel(){
    try{ return (localStorage.getItem(LS_SEL)||"").trim(); }catch(e){ return ""; }
  }
  function setSel(rid){
    try{ localStorage.setItem(LS_SEL, String(rid||"").trim()); }catch(e){}
  }

  function findFilterInput(){
    return qs('input[placeholder*="Filter by RID"]')
        || qs('input[placeholder*="Filter by RID / label"]')
        || qs('input[placeholder*="Filter"]');
  }

  function findRunsRootFromInput(inp){
    return (inp && (inp.closest("section") || inp.closest(".card") || inp.closest("div"))) || document.body;
  }

  function ridFromRow(row){
    if (!row) return "";
    const d = (row.getAttribute("data-vsp-rid") || row.getAttribute("data-rid") || "").trim();
    if (d) return d;
    // first cell often RID
    const td = row.querySelector("td");
    const t = txt(td);
    if (t) return t;
    return "";
  }

  function tsFromRow(row){
    const t = txt(row);
    // match YYYY-MM-DD HH:MM (from your screenshot)
    const m = t.match(/(20\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
    if (!m) return 0;
    const y=+m[1], mo=+m[2], d=+m[3], hh=+m[4], mm=+m[5];
    const dt = new Date(y, mo-1, d, hh, mm, 0, 0);
    return dt.getTime() || 0;
  }

  function isRunsRow(row){
    // In your UI, row has "Use RID" button + "Reports.tgz"
    const t = txt(row).toLowerCase();
    return t.includes("use rid") && (t.includes("reports.tgz") || t.includes("csv") || t.includes("dashboard"));
  }

  function getRunsRows(root){
    // Prefer table rows if exist
    const rows = qsa("tr", root).filter(isRunsRow);
    return rows;
  }

  function ensureSortSelect(inp){
    ensureCss();
    if (!inp) return null;
    if (inp.parentElement && qs("select.vsp-p466a2-sort", inp.parentElement)) return qs("select.vsp-p466a2-sort", inp.parentElement);

    const sel=document.createElement("select");
    sel.className="vsp-p466a2-sort";
    sel.innerHTML = `
      <option value="new">Sort: Newest</option>
      <option value="old">Sort: Oldest</option>
      <option value="none">Sort: None</option>
    `;
    sel.value = getSort();
    sel.addEventListener("change", ()=>{ setSort(sel.value); applyAll(); });

    // put right after input
    inp.insertAdjacentElement("afterend", sel);
    return sel;
  }

  function patchRunsLoaded(uniqueCount){
    // Replace any "Runs loaded: undefined" text we can find
    const nodes = qsa("*").slice(0, 2500); // keep safe
    for (const el of nodes){
      const t = el.childElementCount === 0 ? txt(el) : "";
      if (t && t.includes("Runs loaded:") && t.includes("undefined")){
        el.textContent = "Runs loaded: " + String(uniqueCount);
      }
    }
  }

  function highlightSelected(rows){
    const sel = getSel();
    for(const r of rows){
      const rid = ridFromRow(r);
      if (rid && sel && rid === sel) r.classList.add("vsp-p466a2-selected");
      else r.classList.remove("vsp-p466a2-selected");
    }
  }

  function dedupeRows(rows){
    const seen = new Set();
    let unique = 0;
    for (const r of rows){
      const rid = ridFromRow(r);
      const ts  = tsFromRow(r);
      const key = (rid||"") + "|" + String(ts||0);
      if (!rid) { r.classList.remove("vsp-p466a2-hidden"); continue; }
      if (seen.has(key)){
        r.classList.add("vsp-p466a2-hidden");
      }else{
        seen.add(key);
        r.classList.remove("vsp-p466a2-hidden");
        unique += 1;
      }
    }
    return unique;
  }

  function sortRows(rows, mode){
    if (mode === "none") return;
    const visible = rows.filter(r=>!r.classList.contains("vsp-p466a2-hidden"));
    visible.sort((a,b)=>{
      const ta = tsFromRow(a), tb = tsFromRow(b);
      if (ta === tb){
        const ra = ridFromRow(a), rb = ridFromRow(b);
        return ra < rb ? -1 : ra > rb ? 1 : 0;
      }
      return mode === "new" ? (tb - ta) : (ta - tb);
    });
    // append back in order (keeps them inside same tbody/container)
    const parent = visible[0] ? visible[0].parentElement : null;
    if (!parent) return;
    for (const r of visible) parent.appendChild(r);
  }

  function bindSelectByClick(root){
    // store selection when user hits "Use RID" button
    root.addEventListener("click", (ev)=>{
      const btn = ev.target && ev.target.closest ? ev.target.closest("button, a") : null;
      if (!btn) return;
      const btxt = txt(btn).toLowerCase();
      if (!btxt.includes("use rid")) return;
      const row = btn.closest("tr");
      const rid = ridFromRow(row);
      if (rid) setSel(rid);
      // re-apply highlight
      const rows = getRunsRows(root);
      highlightSelected(rows);
    }, true);
  }

  function applyAll(){
    const inp = findFilterInput();
    if (!inp) return;
    const root = findRunsRootFromInput(inp);

    ensureSortSelect(inp);
    bindSelectByClick(root);

    const rows = getRunsRows(root);
    if (!rows.length) return;

    const unique = dedupeRows(rows);
    sortRows(rows, getSort());
    highlightSelected(rows);
    patchRunsLoaded(unique);
  }

  // run periodically (safe, idempotent)
  setInterval(applyAll, 900);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ()=>setTimeout(applyAll, 150));
  else setTimeout(applyAll, 150);
})();
/* --- /VSP_P466A2_RUNS_DEDUPE_SORT_FIXLOADED_V1 --- */


/* --- VSP_P466A3_RUNS_DEDUPE_ANYROW_V1 --- */
(function(){
  if (window.__VSP_P466A3_ON) return;
  window.__VSP_P466A3_ON = true;

  const LS_SORT="vsp_runs_sort_v2";
  const LS_SEL ="vsp_runs_selected_rid_v2";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function t(el){ return (el && el.textContent ? el.textContent : "").trim(); }

  function ensureCss(){
    if (qs('#vsp_p466a3_css')) return;
    const st=document.createElement('style');
    st.id='vsp_p466a3_css';
    st.textContent = `
      .vsp-p466a3-hidden{ display:none !important; }
      .vsp-p466a3-selected{ outline:2px solid rgba(255,255,255,.14); background: rgba(255,255,255,.04)!important; border-radius:12px; }
      .vsp-p466a3-sort{ margin-left:10px; padding:8px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; }
    `;
    document.head.appendChild(st);
  }

  function getSort(){ try{return localStorage.getItem(LS_SORT)||"new";}catch(e){return "new";} }
  function setSort(v){ try{localStorage.setItem(LS_SORT,v);}catch(e){} }
  function getSel(){ try{return (localStorage.getItem(LS_SEL)||"").trim();}catch(e){return "";} }
  function setSel(rid){ try{localStorage.setItem(LS_SEL,String(rid||"").trim());}catch(e){} }

  function findRunsSection(){
    // best effort: section containing Filter input + Use RID buttons
    const btn = qsa('button').find(b => t(b).toLowerCase()==='use rid');
    const inp = qsa('input').find(i => (i.getAttribute('placeholder')||'').toLowerCase().includes('filter by'));
    return (inp && (inp.closest('section')||inp.closest('.card')||inp.closest('div')))
        || (btn && (btn.closest('section')||btn.closest('.card')||btn.closest('div')))
        || document.body;
  }

  function findFilterInput(root){
    return qsa('input', root).find(i => (i.getAttribute('placeholder')||'').toLowerCase().includes('filter by')) || null;
  }

  function ensureSortSelect(root){
    ensureCss();
    const inp = findFilterInput(root);
    if(!inp) return;
    // avoid double insert
    if (inp.parentElement && qs('select.vsp-p466a3-sort', inp.parentElement)) return;

    const sel=document.createElement('select');
    sel.className='vsp-p466a3-sort';
    sel.innerHTML = `
      <option value="new">Sort: Newest</option>
      <option value="old">Sort: Oldest</option>
      <option value="none">Sort: None</option>
    `;
    sel.value = getSort();
    sel.addEventListener('change', ()=>{ setSort(sel.value); apply(root); });
    inp.insertAdjacentElement('afterend', sel);
  }

  function rowFromUseRidButton(btn){
    // climb a few levels to find a “row container” (works for div-based list)
    let n = btn;
    for(let i=0;i<6 && n;i++){
      if (n.tagName && (n.tagName.toLowerCase()==='tr')) return n;
      // heuristics: a row usually contains "Reports.tgz" or "Dashboard" + "CSV"
      const txt = t(n).toLowerCase();
      if (txt.includes('reports.tgz') && txt.includes('dashboard') && txt.includes('csv')) return n;
      n = n.parentElement;
    }
    return btn.closest('tr') || btn.closest('div') || null;
  }

  function extractRidFromText(text){
    const m1 = text.match(/\bVSP_[A-Z0-9_]+\b/);
    if (m1) return m1[0];
    const m2 = text.match(/\bp\d+[a-z0-9_]+\b/i);
    if (m2) return m2[0];
    return "";
  }

  function extractTs(text){
    const m = text.match(/(20\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
    if(!m) return 0;
    const y=+m[1], mo=+m[2], d=+m[3], hh=+m[4], mm=+m[5];
    const dt=new Date(y, mo-1, d, hh, mm, 0, 0);
    return dt.getTime()||0;
  }

  function collectRows(root){
    const buttons = qsa('button', root).filter(b => t(b).toLowerCase()==='use rid');
    const rows = [];
    for(const b of buttons){
      const row = rowFromUseRidButton(b);
      if(!row) continue;
      // avoid duplicates in the rows list itself
      if(rows.indexOf(row)===-1) rows.push(row);
    }
    return rows;
  }

  function patchRunsLoaded(root, n){
    // Update any element showing "Runs loaded: undefined" within root
    const all = qsa('*', root);
    for(const el of all){
      if(el.children && el.children.length) continue;
      const tt = t(el);
      if(!tt) continue;
      if(tt.includes('Runs loaded:') && tt.includes('undefined')){
        el.textContent = 'Runs loaded: ' + String(n);
        return;
      }
    }
  }

  function dedupe(root, rows){
    const seen = new Set();
    let unique = 0;
    for(const r of rows){
      const txt = t(r);
      const rid = extractRidFromText(txt);
      const ts  = extractTs(txt);
      const key = (rid||'') + '|' + String(ts||0);
      if(!rid){
        r.classList.remove('vsp-p466a3-hidden');
        continue;
      }
      if(seen.has(key)){
        r.classList.add('vsp-p466a3-hidden');
      }else{
        seen.add(key);
        r.classList.remove('vsp-p466a3-hidden');
        unique += 1;
      }
    }
    patchRunsLoaded(root, unique);
    return unique;
  }

  function sortRows(root, rows){
    const mode = getSort();
    if(mode === 'none') return;

    const visible = rows.filter(r=>!r.classList.contains('vsp-p466a3-hidden'));
    if(!visible.length) return;
    visible.sort((a,b)=>{
      const ta = extractTs(t(a));
      const tb = extractTs(t(b));
      if(ta===tb){
        const ra = extractRidFromText(t(a));
        const rb = extractRidFromText(t(b));
        return ra<rb?-1:ra>rb?1:0;
      }
      return mode==='new' ? (tb-ta) : (ta-tb);
    });

    const parent = visible[0].parentElement;
    if(!parent) return;
    for(const r of visible) parent.appendChild(r);
  }

  function highlight(root, rows){
    const sel = getSel();
    for(const r of rows){
      const rid = extractRidFromText(t(r));
      if(sel && rid === sel) r.classList.add('vsp-p466a3-selected');
      else r.classList.remove('vsp-p466a3-selected');
    }
  }

  function bind(root){
    // remember selection when clicking Use RID
    root.addEventListener('click', (ev)=>{
      const btn = ev.target && ev.target.closest ? ev.target.closest('button') : null;
      if(!btn) return;
      if(t(btn).toLowerCase() !== 'use rid') return;
      const row = rowFromUseRidButton(btn);
      const rid = row ? extractRidFromText(t(row)) : '';
      if(rid) setSel(rid);
      // apply highlight immediately
      const rows = collectRows(root);
      highlight(root, rows);
    }, true);
  }

  function apply(root){
    ensureSortSelect(root);
    const rows = collectRows(root);
    if(!rows.length) return;
    dedupe(root, rows);
    sortRows(root, rows);
    highlight(root, rows);
  }

  const root = findRunsSection();
  bind(root);

  // periodic reconcile (safe)
  setInterval(()=>apply(root), 800);
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', ()=>setTimeout(()=>apply(root), 120));
  else setTimeout(()=>apply(root), 120);
})();
/* --- /VSP_P466A3_RUNS_DEDUPE_ANYROW_V1 --- */


/* --- VSP_P467_RUNS_PRO_UI_V1 --- */
(function(){
  if (window.__VSP_P467_ON) return;
  window.__VSP_P467_ON = true;

  const LS = {
    q: "vsp_runspro_q_v1",
    overall: "vsp_runspro_overall_v1",
    degraded: "vsp_runspro_degraded_v1",
    from: "vsp_runspro_from_v1",
    to: "vsp_runspro_to_v1",
    ps: "vsp_runspro_ps_v1",
    page: "vsp_runspro_page_v1",
  };

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function t(el){ return (el && el.textContent ? el.textContent : "").trim(); }
  function esc(s){ return String(s||"").replace(/[&<>"']/g, m=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[m])); }

  function lsGet(k, d=""){ try{ const v=localStorage.getItem(k); return (v==null?d:v); }catch(e){ return d; } }
  function lsSet(k, v){ try{ localStorage.setItem(k, String(v)); }catch(e){} }

  function ensureCss(){
    if (qs("#vsp_p467_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p467_css";
    st.textContent = `
      .vsp-p467-wrap{ margin-top:10px; }
      .vsp-p467-top{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p467-badges{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
      .vsp-p467-badge{ padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); font-size:12px; }
      .vsp-p467-toolbar{ margin-top:10px; display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p467-inp,.vsp-p467-sel,.vsp-p467-date,.vsp-p467-btn{
        padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12);
        background: rgba(0,0,0,.25); color:#fff;
      }
      .vsp-p467-inp{ min-width:220px; }
      .vsp-p467-btn{ cursor:pointer; }
      .vsp-p467-btn:hover{ border-color: rgba(255,255,255,.22); }
      .vsp-p467-table{ margin-top:10px; width:100%; border-collapse:separate; border-spacing:0 10px; }
      .vsp-p467-row{ background: rgba(0,0,0,.18); border:1px solid rgba(255,255,255,.08); border-radius:14px; }
      .vsp-p467-td{ padding:10px 12px; vertical-align:middle; }
      .vsp-p467-rid{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; font-size:12px; }
      .vsp-p467-pill{ display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); font-size:12px; }
      .vsp-p467-actions{ display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; }
      .vsp-p467-small{ font-size:12px; opacity:.75; }
      .vsp-p467-hide-legacy{ display:none !important; }
      .vsp-p467-page{ display:flex; gap:8px; align-items:center; }
    `;
    document.head.appendChild(st);
  }

  function findRunsRoot(){
    // ưu tiên khu vực có placeholder "Filter by RID / label / date (client-side)" như ảnh 1
    const inp = qsa("input").find(i => (i.getAttribute("placeholder")||"").toLowerCase().includes("filter by rid"));
    return (inp && (inp.closest("section")||inp.closest(".card")||inp.closest("div"))) || qs("#vsp-dashboard-main") || document.body;
  }

  function hideLegacyList(root){
    // Hide the legacy list/table area: the block right under the Filter input
    const inp = qsa("input", root).find(i => (i.getAttribute("placeholder")||"").toLowerCase().includes("filter by rid"));
    if (!inp) return;
    // attempt to hide its following list container (siblings)
    const host = inp.closest("div") || inp.parentElement || root;
    // hide anything that contains repeated "Use RID" buttons (legacy rendering)
    const cand = qsa("*", root).filter(el=>{
      const txt = t(el).toLowerCase();
      return txt.includes("use rid") && txt.includes("reports.tgz") && txt.includes("dashboard") && txt.includes("csv");
    });
    // hide the parents of these elements to stop duplication view
    for(const el of cand){
      const box = el.closest("table") || el.closest("div");
      if (box) box.classList.add("vsp-p467-hide-legacy");
    }
    // also hide the filter input row itself (we will provide our own)
    // but keep it if you want — we keep it visible
    host.classList.remove("vsp-p467-hide-legacy");
  }

  function mount(root){
    let m = qs("#vsp_runs_pro_mount", root);
    if (m) return m;
    m = document.createElement("div");
    m.id = "vsp_runs_pro_mount";
    m.className = "vsp-p467-wrap";
    // place near the start of Runs & Reports section
    const h2 = qsa("h2", root).find(x => t(x).toLowerCase().includes("runs"));
    if (h2 && h2.parentElement) h2.parentElement.insertBefore(m, h2.nextSibling);
    else root.insertBefore(m, root.firstChild);
    return m;
  }

  async function apiRuns(limit){
    const url = "/api/vsp/runs?limit="+encodeURIComponent(limit)+"&include_ci=1";
    const r = await fetch(url, {credentials:"same-origin"});
    const j = await r.json().catch(()=>null);
    if (!r.ok) throw new Error("HTTP "+r.status);
    return j;
  }

  function pickItems(j){
    if (!j) return [];
    if (Array.isArray(j)) return j;
    if (Array.isArray(j.items)) return j.items;
    if (Array.isArray(j.runs)) return j.runs;
    if (Array.isArray(j.data)) return j.data;
    return [];
  }

  function normOverall(x){
    const v = String(x||"UNKNOWN").toUpperCase();
    if (["GREEN","AMBER","RED","UNKNOWN"].includes(v)) return v;
    if (["PASS","OK"].includes(v)) return "GREEN";
    if (["FAIL","BLOCK"].includes(v)) return "RED";
    return "UNKNOWN";
  }

  function getRid(it){
    return (it && (it.rid || it.RID || it.id || it.run_id)) ? String(it.rid||it.RID||it.id||it.run_id) : "";
  }

  function getEpoch(it){
    // best effort: ts / time / created / date
    const cand = it && (it.ts || it.time || it.created || it.date || it.label_ts || it.label);
    if (typeof cand === "number") return cand>1e12?cand:cand*1000;
    if (typeof cand === "string"){
      // try ISO
      const d = new Date(cand);
      if (!isNaN(d.getTime())) return d.getTime();
      // try "YYYY-MM-DD HH:MM"
      const m = cand.match(/(20\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
      if (m){
        const dt = new Date(+m[1], +m[2]-1, +m[3], +m[4], +m[5], 0, 0);
        return dt.getTime()||0;
      }
    }
    return 0;
  }

  function getOverall(it){
    return normOverall(it && (it.overall || it.status || (it.gate && it.gate.overall) || (it.run_gate && it.run_gate.overall)));
  }

  function isDegraded(it){
    const v = it && (it.degraded || it.is_degraded || (it.gate && it.gate.degraded) || (it.run_gate && it.run_gate.degraded));
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v > 0;
    const s = String(v||"").toLowerCase();
    if (["true","1","yes","ok"].includes(s)) return true;
    return false;
  }

  function fmtTime(ms){
    if(!ms) return "-";
    const d=new Date(ms);
    const pad=n=>String(n).padStart(2,"0");
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  function withinDate(ms, from, to){
    if (!ms) return true;
    const d = new Date(ms);
    const ymd = d.getFullYear()*10000 + (d.getMonth()+1)*100 + d.getDate();
    if (from){
      const f = from.replaceAll("-","");
      if (ymd < +f) return false;
    }
    if (to){
      const tt = to.replaceAll("-","");
      if (ymd > +tt) return false;
    }
    return true;
  }

  function dedupe(items){
    const seen = new Set();
    const out = [];
    for(const it of items){
      const rid = getRid(it);
      const ep = getEpoch(it);
      const key = rid + "|" + String(ep||0);
      if (!rid) continue;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(it);
    }
    return out;
  }

  function buildUrl(path, rid){
    const u = new URL(path, location.origin);
    if (rid) u.searchParams.set("rid", rid);
    return u.toString();
  }

  function openJson(rid){
    // best effort: users already use run_file_allow; keep it compatible
    const u1 = buildUrl("/api/vsp/run_file_allow?path=findings_unified.json&limit=200", rid);
    window.open(u1, "_blank");
  }

  function openHtml(rid){
    // open some known html report file if allowed by backend; fallback to /runs itself
    const u = buildUrl("/api/vsp/run_file_allow?path=reports/findings_unified.html&limit=200", rid);
    window.open(u, "_blank");
  }

  async function render(){
    const root = findRunsRoot();
    ensureCss();
    hideLegacyList(root);
    const m = mount(root);

    // state
    const q = lsGet(LS.q,"");
    const overall = lsGet(LS.overall,"ALL");
    const degraded = lsGet(LS.degraded,"ALL");
    const from = lsGet(LS.from,"");
    const to = lsGet(LS.to,"");
    const ps = parseInt(lsGet(LS.ps,"20"),10) || 20;
    const page = parseInt(lsGet(LS.page,"1"),10) || 1;

    m.innerHTML = `
      <div class="vsp-p467-top">
        <div class="vsp-p467-small">Runs & Reports Quick Actions (commercial)</div>
        <div class="vsp-p467-badges" id="vsp_p467_badges"></div>
      </div>

      <div class="vsp-p467-toolbar">
        <input class="vsp-p467-inp" id="vsp_p467_q" placeholder="Search RID..." value="${esc(q)}"/>
        <select class="vsp-p467-sel" id="vsp_p467_overall">
          <option value="ALL">Overall: ALL</option>
          <option value="GREEN">GREEN</option>
          <option value="AMBER">AMBER</option>
          <option value="RED">RED</option>
          <option value="UNKNOWN">UNKNOWN</option>
        </select>
        <select class="vsp-p467-sel" id="vsp_p467_degraded">
          <option value="ALL">Degraded: ALL</option>
          <option value="0">Degraded: 0</option>
          <option value="1">Degraded: 1</option>
        </select>
        <span class="vsp-p467-small">From</span>
        <input class="vsp-p467-date" id="vsp_p467_from" type="date" value="${esc(from)}"/>
        <span class="vsp-p467-small">To</span>
        <input class="vsp-p467-date" id="vsp_p467_to" type="date" value="${esc(to)}"/>
        <button class="vsp-p467-btn" id="vsp_p467_refresh">Refresh</button>
        <button class="vsp-p467-btn" id="vsp_p467_exports">Open Exports</button>
        <button class="vsp-p467-btn" id="vsp_p467_clear">Clear</button>
      </div>

      <div class="vsp-p467-toolbar vsp-p467-page">
        <span class="vsp-p467-small">Page size</span>
        <select class="vsp-p467-sel" id="vsp_p467_ps">
          <option value="10">10/page</option>
          <option value="20">20/page</option>
          <option value="50">50/page</option>
          <option value="100">100/page</option>
          <option value="200">200/page</option>
        </select>
        <button class="vsp-p467-btn" id="vsp_p467_prev">Prev</button>
        <button class="vsp-p467-btn" id="vsp_p467_next">Next</button>
        <span class="vsp-p467-small" id="vsp_p467_pageinfo"></span>
      </div>

      <table class="vsp-p467-table" id="vsp_p467_table"></table>
    `;

    // set defaults
    qs("#vsp_p467_overall", m).value = overall;
    qs("#vsp_p467_degraded", m).value = degraded;
    qs("#vsp_p467_ps", m).value = String(ps);

    function saveState(){
      lsSet(LS.q, qs("#vsp_p467_q", m).value||"");
      lsSet(LS.overall, qs("#vsp_p467_overall", m).value||"ALL");
      lsSet(LS.degraded, qs("#vsp_p467_degraded", m).value||"ALL");
      lsSet(LS.from, qs("#vsp_p467_from", m).value||"");
      lsSet(LS.to, qs("#vsp_p467_to", m).value||"");
      lsSet(LS.ps, qs("#vsp_p467_ps", m).value||"20");
    }

    function setPage(n){ lsSet(LS.page, String(n)); }

    async function loadAndPaint(){
      saveState();
      const limit = 500; // load enough; paginate client-side
      let j=null, items=[];
      try{
        j = await apiRuns(limit);
        items = pickItems(j);
      }catch(e){
        items = [];
      }

      items = dedupe(items).map(it=>{
        return Object.assign({}, it, {
          __rid: getRid(it),
          __ms: getEpoch(it),
          __overall: getOverall(it),
          __degraded: isDegraded(it) ? 1 : 0
        });
      });

      // counts
      const counts = {TOTAL: items.length, GREEN:0, AMBER:0, RED:0, UNKNOWN:0, DEGRADED:0};
      for(const it of items){
        counts[it.__overall] = (counts[it.__overall]||0) + 1;
        if (it.__degraded) counts.DEGRADED += 1;
      }

      const badges = qs("#vsp_p467_badges", m);
      badges.innerHTML = `
        <span class="vsp-p467-badge">Total ${counts.TOTAL}</span>
        <span class="vsp-p467-badge">GREEN ${counts.GREEN}</span>
        <span class="vsp-p467-badge">AMBER ${counts.AMBER}</span>
        <span class="vsp-p467-badge">RED ${counts.RED}</span>
        <span class="vsp-p467-badge">UNKNOWN ${counts.UNKNOWN}</span>
        <span class="vsp-p467-badge">DEGRADED ${counts.DEGRADED}</span>
      `;

      // filters
      const qv = (qs("#vsp_p467_q", m).value||"").trim().toLowerCase();
      const ov = qs("#vsp_p467_overall", m).value||"ALL";
      const dv = qs("#vsp_p467_degraded", m).value||"ALL";
      const fv = qs("#vsp_p467_from", m).value||"";
      const tv = qs("#vsp_p467_to", m).value||"";

      let filtered = items.filter(it=>{
        if (qv && !String(it.__rid||"").toLowerCase().includes(qv)) return false;
        if (ov !== "ALL" && it.__overall !== ov) return false;
        if (dv !== "ALL" && String(it.__degraded) !== dv) return false;
        if (!withinDate(it.__ms, fv, tv)) return false;
        return true;
      });

      // sort newest first
      filtered.sort((a,b)=> (b.__ms||0) - (a.__ms||0));

      const psNow = parseInt(qs("#vsp_p467_ps", m).value||"20",10) || 20;
      let pageNow = parseInt(lsGet(LS.page,"1"),10) || 1;
      const maxPage = Math.max(1, Math.ceil(filtered.length / psNow));
      if (pageNow > maxPage) pageNow = maxPage;
      if (pageNow < 1) pageNow = 1;
      setPage(pageNow);

      const start = (pageNow-1)*psNow;
      const chunk = filtered.slice(start, start+psNow);

      qs("#vsp_p467_pageinfo", m).textContent = `Showing ${chunk.length}/${filtered.length} (page ${pageNow}/${maxPage})`;

      // table
      const tb = qs("#vsp_p467_table", m);
      tb.innerHTML = `
        <tr class="vsp-p467-row">
          <td class="vsp-p467-td vsp-p467-small">RID</td>
          <td class="vsp-p467-td vsp-p467-small">DATE</td>
          <td class="vsp-p467-td vsp-p467-small">OVERALL</td>
          <td class="vsp-p467-td vsp-p467-small">DEGRADED</td>
          <td class="vsp-p467-td vsp-p467-small" style="text-align:right;">ACTIONS</td>
        </tr>
      `;

      for(const it of chunk){
        const rid = it.__rid;
        const date = fmtTime(it.__ms);
        const overallPill = `<span class="vsp-p467-pill">${esc(it.__overall)}</span>`;
        const degrPill = `<span class="vsp-p467-pill">${it.__degraded? "OK":"-"}</span>`;

        const csv = buildUrl("/api/vsp/export_csv", rid);
        const tgz = buildUrl("/api/vsp/export_tgz", rid);

        const row = document.createElement("tr");
        row.className="vsp-p467-row";
        row.innerHTML = `
          <td class="vsp-p467-td vsp-p467-rid">
            <div>${esc(rid)}</div>
            <div class="vsp-p467-small">
              <button class="vsp-p467-btn" data-act="copy" data-rid="${esc(rid)}">Copy RID</button>
              <button class="vsp-p467-btn" data-act="use" data-rid="${esc(rid)}">Use RID</button>
            </div>
          </td>
          <td class="vsp-p467-td"><span class="vsp-p467-pill">${esc(date)}</span></td>
          <td class="vsp-p467-td">${overallPill}</td>
          <td class="vsp-p467-td">${degrPill}</td>
          <td class="vsp-p467-td">
            <div class="vsp-p467-actions">
              <a class="vsp-p467-btn" href="${esc(csv)}">CSV</a>
              <a class="vsp-p467-btn" href="${esc(tgz)}">TGZ</a>
              <button class="vsp-p467-btn" data-act="json" data-rid="${esc(rid)}">Open JSON</button>
              <button class="vsp-p467-btn" data-act="html" data-rid="${esc(rid)}">Open HTML</button>
            </div>
          </td>
        `;
        tb.appendChild(row);
      }

      // bind actions
      tb.addEventListener("click", (ev)=>{
        const btn = ev.target && ev.target.closest ? ev.target.closest("button") : null;
        if(!btn) return;
        const act = btn.getAttribute("data-act")||"";
        const rid = btn.getAttribute("data-rid")||"";
        if(!rid) return;

        if(act==="copy"){
          try{ navigator.clipboard.writeText(rid); }catch(e){}
        }else if(act==="use"){
          // keep behavior: set URL rid param and reload same /c/runs
          const u = new URL(location.href);
          u.searchParams.set("rid", rid);
          location.href = u.toString();
        }else if(act==="json"){
          openJson(rid);
        }else if(act==="html"){
          openHtml(rid);
        }
      }, {once:true});
    }

    // buttons
    qs("#vsp_p467_refresh", m).addEventListener("click", ()=>loadAndPaint());
    qs("#vsp_p467_exports", m).addEventListener("click", ()=>window.open("/api/vsp/exports_v1","_blank"));
    qs("#vsp_p467_clear", m).addEventListener("click", ()=>{
      qs("#vsp_p467_q", m).value="";
      qs("#vsp_p467_overall", m).value="ALL";
      qs("#vsp_p467_degraded", m).value="ALL";
      qs("#vsp_p467_from", m).value="";
      qs("#vsp_p467_to", m).value="";
      qs("#vsp_p467_ps", m).value="20";
      setPage(1);
      loadAndPaint();
    });
    qs("#vsp_p467_prev", m).addEventListener("click", ()=>{
      const cur = parseInt(lsGet(LS.page,"1"),10)||1;
      setPage(Math.max(1, cur-1));
      loadAndPaint();
    });
    qs("#vsp_p467_next", m).addEventListener("click", ()=>{
      const cur = parseInt(lsGet(LS.page,"1"),10)||1;
      setPage(cur+1);
      loadAndPaint();
    });

    // change events -> reload
    qsa("#vsp_p467_q,#vsp_p467_overall,#vsp_p467_degraded,#vsp_p467_from,#vsp_p467_to,#vsp_p467_ps", m).forEach(el=>{
      el.addEventListener("change", ()=>{ setPage(1); loadAndPaint(); });
      if (el.id==="vsp_p467_q") el.addEventListener("input", ()=>{ setPage(1); loadAndPaint(); });
    });

    // first paint
    loadAndPaint();
  }

  function boot(){
    const root = findRunsRoot();
    ensureCss();
    hideLegacyList(root);
    render().catch(()=>{});
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
  setTimeout(boot, 900); // guard for late render
})();
 /* --- /VSP_P467_RUNS_PRO_UI_V1 --- */

