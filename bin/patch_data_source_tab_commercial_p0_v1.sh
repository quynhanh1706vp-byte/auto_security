#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3
need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

APP="vsp_demo_app.py"
TPL="templates/vsp_data_source_2025.html"
JS="static/js/vsp_data_source_tab_v1.js"
CSS="static/css/vsp_data_source_tab_v1.css"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
mkdir -p "$(dirname "$TPL")" "$(dirname "$JS")" "$(dirname "$CSS")" out_ci

# backups
cp -f "$APP" "${APP}.bak_data_${TS}"
echo "[BACKUP] ${APP}.bak_data_${TS}"
[ -f "$TPL" ] && cp -f "$TPL" "${TPL}.bak_${TS}" && echo "[BACKUP] ${TPL}.bak_${TS}" || true
[ -f "$JS"  ] && cp -f "$JS"  "${JS}.bak_${TS}"  && echo "[BACKUP] ${JS}.bak_${TS}"  || true
[ -f "$CSS" ] && cp -f "$CSS" "${CSS}.bak_${TS}" && echo "[BACKUP] ${CSS}.bak_${TS}" || true

# (1) write template
cat > "$TPL" <<'HTML'
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>VSP • Data Source</title>
  <link rel="stylesheet" href="/static/css/vsp_data_source_tab_v1.css?v=VSP_DATA_P0_V1"/>
</head>
<body>
  <div class="topbar">
    <div class="brand">
      <span class="dot"></span>
      <div class="title">VersaSecure Platform • UI</div>
      <div class="subtitle">Data Source (Findings)</div>
    </div>

    <div class="tabs">
      <a class="tab" href="/vsp4">Dashboard</a>
      <a class="tab" href="/runs">Runs &amp; Reports</a>
      <a class="tab active" href="/data">Data Source</a>
      <a class="tab" href="/settings">Settings</a>
      <a class="tab" href="/rule_overrides">Rule Overrides</a>
    </div>

    <div class="actions">
      <button id="btnReload" class="btn">Reload</button>
      <a class="btn btn-ghost" href="/api/vsp/findings" target="_blank" rel="noopener">Open API</a>
    </div>
  </div>

  <div class="wrap">
    <div class="panel">
      <div class="panel-head">
        <div class="kpis">
          <div class="kpi">
            <div class="kpi-label">Total</div>
            <div id="kpiTotal" class="kpi-val">—</div>
          </div>
          <div class="kpi">
            <div class="kpi-label">Shown</div>
            <div id="kpiShown" class="kpi-val">—</div>
          </div>
          <div class="kpi">
            <div class="kpi-label">Last fetch</div>
            <div id="kpiFetched" class="kpi-val">—</div>
          </div>
        </div>

        <div class="controls">
          <input id="q" class="input" placeholder="Search (rule/id/title/message/path/tool) …" />
          <select id="sev" class="select">
            <option value="">All severities</option>
            <option value="CRITICAL">CRITICAL</option>
            <option value="HIGH">HIGH</option>
            <option value="MEDIUM">MEDIUM</option>
            <option value="LOW">LOW</option>
            <option value="INFO">INFO</option>
            <option value="TRACE">TRACE</option>
          </select>
          <select id="tool" class="select">
            <option value="">All tools</option>
          </select>
          <select id="sort" class="select">
            <option value="sev_desc">Sort: Severity ↓</option>
            <option value="sev_asc">Sort: Severity ↑</option>
            <option value="tool_asc">Sort: Tool A→Z</option>
            <option value="file_asc">Sort: File A→Z</option>
            <option value="rule_asc">Sort: Rule/ID A→Z</option>
          </select>

          <select id="pageSize" class="select">
            <option value="25">25 / page</option>
            <option value="50" selected>50 / page</option>
            <option value="100">100 / page</option>
            <option value="250">250 / page</option>
          </select>
        </div>

        <div id="banner" class="banner hidden"></div>
      </div>

      <div class="table-wrap">
        <table class="tbl">
          <thead>
            <tr>
              <th style="width:120px;">Severity</th>
              <th style="width:150px;">Tool</th>
              <th>Title / Rule</th>
              <th style="width:36%;">File / Location</th>
              <th style="width:160px;">Actions</th>
            </tr>
          </thead>
          <tbody id="rows">
            <tr><td colspan="5" class="muted">Loading…</td></tr>
          </tbody>
        </table>
      </div>

      <div class="pager">
        <div class="muted" id="pagerInfo">—</div>
        <div class="pagerBtns">
          <button class="btn btn-ghost" id="btnPrev">Prev</button>
          <button class="btn btn-ghost" id="btnNext">Next</button>
        </div>
      </div>
    </div>

    <div class="foot muted">
      Contract source: <code>/api/vsp/findings</code> • UI: <code>/data</code>
    </div>
  </div>

  <!-- modal -->
  <div id="modal" class="modal hidden">
    <div class="modal-backdrop" id="modalClose"></div>
    <div class="modal-card">
      <div class="modal-head">
        <div>
          <div id="mTitle" class="modal-title">Finding</div>
          <div id="mSub" class="modal-sub muted">—</div>
        </div>
        <div class="modal-actions">
          <button id="btnCopyJSON" class="btn">Copy JSON</button>
          <button id="btnClose" class="btn btn-ghost">Close</button>
        </div>
      </div>
      <pre id="mJson" class="modal-pre">{}</pre>
    </div>
  </div>

  <script src="/static/js/vsp_data_source_tab_v1.js?v=VSP_DATA_P0_V1"></script>
</body>
</html>
HTML
echo "[OK] wrote $TPL"

# (2) write css (dark commercial)
cat > "$CSS" <<'CSS'
:root{
  --bg:#0b0f16;
  --panel:#0f1623;
  --panel2:#0c121d;
  --text:#e7eefc;
  --muted:#9aa8c7;
  --line:#1c2a42;
  --chip:#121c2b;
  --shadow: 0 12px 40px rgba(0,0,0,.35);
  --radius: 14px;
  --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
  --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji";
}
*{ box-sizing:border-box; }
body{
  margin:0;
  background: radial-gradient(1200px 600px at 10% 10%, rgba(84,145,255,.12), transparent 60%),
              radial-gradient(900px 500px at 90% 20%, rgba(148,84,255,.10), transparent 55%),
              var(--bg);
  color:var(--text);
  font-family:var(--sans);
}
code{ font-family:var(--mono); color:#cfe0ff; }
.topbar{
  position:sticky; top:0; z-index:5;
  display:flex; gap:16px; align-items:center; justify-content:space-between;
  padding:14px 18px;
  border-bottom:1px solid var(--line);
  background: rgba(10,14,22,.85);
  backdrop-filter: blur(10px);
}
.brand{ display:flex; align-items:center; gap:12px; min-width:280px;}
.dot{ width:10px; height:10px; border-radius:999px; background:#39d98a; box-shadow:0 0 0 5px rgba(57,217,138,.15); }
.title{ font-weight:700; letter-spacing:.2px; }
.subtitle{ font-size:12px; color:var(--muted); margin-left:8px; }
.tabs{ display:flex; gap:10px; flex:1; justify-content:center; }
.tab{
  text-decoration:none; color:var(--muted);
  padding:10px 12px; border-radius:999px;
  border:1px solid transparent;
  background:transparent;
  transition: all .15s ease;
  font-weight:600; font-size:13px;
}
.tab:hover{ color:var(--text); border-color:rgba(90,140,255,.25); background:rgba(90,140,255,.10); }
.tab.active{ color:var(--text); border-color:rgba(90,140,255,.35); background:rgba(90,140,255,.16); }
.actions{ display:flex; gap:10px; }
.btn{
  cursor:pointer;
  border:1px solid rgba(90,140,255,.35);
  background:rgba(90,140,255,.16);
  color:var(--text);
  padding:9px 12px;
  border-radius:10px;
  font-weight:700;
}
.btn:hover{ filter:brightness(1.08); }
.btn-ghost{
  border-color: rgba(255,255,255,.12);
  background: rgba(255,255,255,.06);
}
.wrap{ padding:18px; max-width: 1600px; margin:0 auto; }
.panel{
  border:1px solid var(--line);
  border-radius: var(--radius);
  background: linear-gradient(180deg, rgba(255,255,255,.03), rgba(255,255,255,.01));
  box-shadow: var(--shadow);
  overflow:hidden;
}
.panel-head{
  padding:14px 14px 10px 14px;
  border-bottom:1px solid var(--line);
  background: rgba(12,18,29,.55);
}
.kpis{ display:flex; gap:10px; flex-wrap:wrap; margin-bottom:10px; }
.kpi{
  min-width: 170px;
  border:1px solid rgba(255,255,255,.08);
  background: rgba(255,255,255,.04);
  border-radius: 12px;
  padding:10px 12px;
}
.kpi-label{ font-size:12px; color:var(--muted); }
.kpi-val{ font-size:18px; font-weight:800; margin-top:4px; }
.controls{
  display:flex; gap:10px; flex-wrap:wrap; align-items:center;
}
.input, .select{
  border:1px solid rgba(255,255,255,.10);
  background: rgba(255,255,255,.05);
  color: var(--text);
  padding:10px 12px;
  border-radius: 12px;
  outline:none;
}
.input{ min-width: 360px; flex:1; }
.select{ min-width: 170px; }
.banner{
  margin-top:10px;
  padding:10px 12px;
  border-radius:12px;
  border:1px solid rgba(255,110,110,.25);
  background: rgba(255,110,110,.10);
  color:#ffd0d0;
  font-weight:600;
}
.hidden{ display:none !important; }
.table-wrap{ overflow:auto; max-height: calc(100vh - 280px); }
.tbl{ width:100%; border-collapse:collapse; }
.tbl th, .tbl td{
  padding:11px 12px;
  border-bottom:1px solid rgba(255,255,255,.06);
  vertical-align:top;
}
.tbl thead th{
  position:sticky; top:0; z-index:2;
  background: rgba(12,18,29,.95);
  border-bottom:1px solid var(--line);
  text-align:left;
  font-size:12px; letter-spacing:.4px; text-transform:uppercase;
  color: var(--muted);
}
.muted{ color: var(--muted); }
.badge{
  display:inline-flex; align-items:center; gap:8px;
  padding:7px 10px;
  border-radius:999px;
  font-weight:900; font-size:12px;
  border:1px solid rgba(255,255,255,.10);
  background: rgba(255,255,255,.05);
}
.badge .pip{
  width:10px; height:10px; border-radius:999px;
  background: rgba(255,255,255,.25);
}
.badge.CRITICAL{ border-color: rgba(255,70,70,.35); background: rgba(255,70,70,.12); }
.badge.CRITICAL .pip{ background: rgba(255,70,70,.85); }
.badge.HIGH{ border-color: rgba(255,140,0,.35); background: rgba(255,140,0,.12); }
.badge.HIGH .pip{ background: rgba(255,140,0,.85); }
.badge.MEDIUM{ border-color: rgba(255,214,0,.35); background: rgba(255,214,0,.10); }
.badge.MEDIUM .pip{ background: rgba(255,214,0,.85); }
.badge.LOW{ border-color: rgba(90,140,255,.35); background: rgba(90,140,255,.12); }
.badge.LOW .pip{ background: rgba(90,140,255,.85); }
.badge.INFO{ border-color: rgba(140,255,220,.25); background: rgba(140,255,220,.08); }
.badge.INFO .pip{ background: rgba(140,255,220,.70); }
.badge.TRACE{ border-color: rgba(255,255,255,.14); background: rgba(255,255,255,.05); }
.badge.TRACE .pip{ background: rgba(255,255,255,.35); }

.cell-title{ font-weight:800; }
.cell-sub{ margin-top:4px; font-family:var(--mono); font-size:12px; color: #b9c8e6; opacity:.95; }
.path{ font-family:var(--mono); font-size:12px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width: 720px; display:block; }
.actions-mini{ display:flex; gap:8px; flex-wrap:wrap; }
.mbtn{
  cursor:pointer;
  border:1px solid rgba(255,255,255,.12);
  background: rgba(255,255,255,.06);
  color: var(--text);
  padding:7px 9px;
  border-radius: 10px;
  font-weight:800;
  font-size:12px;
}
.mbtn:hover{ filter:brightness(1.08); }
.mbtn.primary{
  border-color: rgba(90,140,255,.35);
  background: rgba(90,140,255,.16);
}

.pager{
  display:flex; align-items:center; justify-content:space-between;
  padding:12px 14px;
  border-top:1px solid rgba(255,255,255,.06);
  background: rgba(12,18,29,.55);
}
.pagerBtns{ display:flex; gap:10px; }
.foot{ margin-top:12px; padding:0 4px; }

.modal{
  position:fixed; inset:0; z-index:20;
  display:flex; align-items:center; justify-content:center;
}
.modal-backdrop{
  position:absolute; inset:0;
  background: rgba(0,0,0,.60);
}
.modal-card{
  position:relative;
  width:min(1100px, 92vw);
  max-height: 86vh;
  border-radius: 16px;
  border:1px solid rgba(255,255,255,.12);
  background: rgba(15,22,35,.96);
  box-shadow: var(--shadow);
  overflow:hidden;
}
.modal-head{
  display:flex; align-items:flex-start; justify-content:space-between;
  gap:12px;
  padding:14px 14px;
  border-bottom:1px solid rgba(255,255,255,.08);
}
.modal-title{ font-size:16px; font-weight:900; }
.modal-sub{ margin-top:4px; font-family:var(--mono); font-size:12px; }
.modal-actions{ display:flex; gap:10px; }
.modal-pre{
  margin:0; padding:14px;
  font-family: var(--mono);
  font-size:12px;
  overflow:auto;
  max-height: calc(86vh - 80px);
  background: rgba(0,0,0,.18);
}
CSS
echo "[OK] wrote $CSS"

# (3) write js (client side filter/sort/paging + drilldown)
cat > "$JS" <<'JS'
(function(){
  'use strict';

  const API = '/api/vsp/findings';
  const $ = (id)=>document.getElementById(id);

  const sevRank = (s)=>{
    s = (s||'').toUpperCase();
    return ({CRITICAL:6,HIGH:5,MEDIUM:4,LOW:3,INFO:2,TRACE:1})[s] || 0;
  };

  const safeStr = (v)=>{
    if (v === null || v === undefined) return '';
    if (typeof v === 'string') return v;
    try { return JSON.stringify(v); } catch(_){ return String(v); }
  };

  const pick = (o, paths)=>{
    for (const p of paths){
      try{
        const parts = p.split('.');
        let cur = o;
        for (const k of parts){
          if (cur && Object.prototype.hasOwnProperty.call(cur, k)) cur = cur[k];
          else { cur = undefined; break; }
        }
        if (cur !== undefined && cur !== null && safeStr(cur)!=='') return cur;
      }catch(_){}
    }
    return undefined;
  };

  const norm = (f)=>{
    const severity = (pick(f, ['severity_norm','severityNormalized','severity','sev','level']) || '').toString().toUpperCase();
    const tool = (pick(f, ['tool','engine','source','scanner','product']) || '').toString();
    const rule = (pick(f, ['rule_id','ruleId','id','check_id','checkId','signature']) || '').toString();
    const title = (pick(f, ['title','message','desc','description','name','summary']) || rule || '(no title)').toString();

    const path = pick(f, ['path','file','filename','location.path','loc.path','meta.path','metadata.path','artifact.path']);
    const line = pick(f, ['line','location.line','loc.line','start.line','region.startLine','metadata.line']);
    const col  = pick(f, ['column','location.column','loc.column','start.col','region.startColumn','metadata.column']);

    const fileLoc = (()=>{
      const p = safeStr(path);
      const l = safeStr(line);
      const c = safeStr(col);
      if (p && (l || c)) return `${p}:${l||''}${c?':'+c:''}`.replace(/:+$/,'');
      if (p) return p;
      return safeStr(pick(f, ['module','component','target','resource'])) || '(no location)';
    })();

    return { severity, tool, rule, title, fileLoc, raw:f };
  };

  let all = [];
  let view = [];
  let page = 0;

  function banner(msg, isErr){
    const b = $('banner');
    if (!msg){ b.classList.add('hidden'); b.textContent=''; return; }
    b.classList.remove('hidden');
    b.style.borderColor = isErr ? 'rgba(255,110,110,.25)' : 'rgba(90,140,255,.30)';
    b.style.background  = isErr ? 'rgba(255,110,110,.10)' : 'rgba(90,140,255,.12)';
    b.style.color       = isErr ? '#ffd0d0' : '#d7e6ff';
    b.textContent = msg;
  }

  async function copyText(s){
    try{
      await navigator.clipboard.writeText(s);
      banner('Copied to clipboard', false);
      setTimeout(()=>banner('', false), 900);
    }catch(_){
      try{
        const ta=document.createElement('textarea');
        ta.value=s; document.body.appendChild(ta);
        ta.select(); document.execCommand('copy');
        ta.remove();
        banner('Copied to clipboard', false);
        setTimeout(()=>banner('', false), 900);
      }catch(e){
        banner('Copy failed: ' + (e && e.message ? e.message : 'unknown'), true);
      }
    }
  }

  function buildToolOptions(items){
    const sel = $('tool');
    const cur = sel.value || '';
    const tools = Array.from(new Set(items.map(x=>x.tool).filter(Boolean).map(x=>String(x)))).sort((a,b)=>a.localeCompare(b));
    sel.innerHTML = '<option value="">All tools</option>' + tools.map(t=>`<option value="${escapeHtml(t)}">${escapeHtml(t)}</option>`).join('');
    sel.value = tools.includes(cur) ? cur : '';
  }

  function escapeHtml(s){
    return String(s||'').replace(/[&<>"']/g, (c)=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }

  function apply(){
    const q = ($('q').value || '').trim().toLowerCase();
    const sev = ($('sev').value || '').toUpperCase();
    const tool = $('tool').value || '';
    const sort = $('sort').value || 'sev_desc';

    view = all.filter(x=>{
      if (sev && (x.severity||'').toUpperCase() !== sev) return false;
      if (tool && x.tool !== tool) return false;
      if (!q) return true;
      const hay = [
        x.severity, x.tool, x.rule, x.title, x.fileLoc,
        safeStr(x.raw && x.raw.cwe), safeStr(x.raw && x.raw.owasp),
        safeStr(x.raw && x.raw.category), safeStr(x.raw && x.raw.control),
      ].join(' ').toLowerCase();
      return hay.includes(q);
    });

    const cmp = {
      sev_desc: (a,b)=> sevRank(b.severity)-sevRank(a.severity) || a.tool.localeCompare(b.tool) || a.title.localeCompare(b.title),
      sev_asc : (a,b)=> sevRank(a.severity)-sevRank(b.severity) || a.tool.localeCompare(b.tool) || a.title.localeCompare(b.title),
      tool_asc: (a,b)=> (a.tool||'').localeCompare(b.tool||'') || sevRank(b.severity)-sevRank(a.severity) || a.title.localeCompare(b.title),
      file_asc: (a,b)=> (a.fileLoc||'').localeCompare(b.fileLoc||'') || sevRank(b.severity)-sevRank(a.severity),
      rule_asc: (a,b)=> (a.rule||'').localeCompare(b.rule||'') || sevRank(b.severity)-sevRank(a.severity),
    }[sort] || null;
    if (cmp) view.sort(cmp);

    page = 0;
    render();
  }

  function render(){
    const pageSize = Math.max(1, parseInt($('pageSize').value||'50',10) || 50);
    const start = page * pageSize;
    const slice = view.slice(start, start + pageSize);

    $('kpiTotal').textContent = String(all.length);
    $('kpiShown').textContent = String(view.length);

    const rows = $('rows');
    if (!slice.length){
      rows.innerHTML = `<tr><td colspan="5" class="muted">No findings match filters.</td></tr>`;
    }else{
      rows.innerHTML = slice.map((x, idx)=>{
        const sev = (x.severity||'').toUpperCase() || 'INFO';
        const tool = x.tool || '';
        const rule = x.rule || '';
        const title = x.title || '';
        const fileLoc = x.fileLoc || '';

        const rid = start + idx;
        return `
          <tr data-rid="${rid}">
            <td>
              <span class="badge ${escapeHtml(sev)}">
                <span class="pip"></span>${escapeHtml(sev)}
              </span>
            </td>
            <td>
              <div class="cell-title">${escapeHtml(tool || '(unknown)')}</div>
            </td>
            <td>
              <div class="cell-title">${escapeHtml(title)}</div>
              <div class="cell-sub">${escapeHtml(rule)}</div>
            </td>
            <td>
              <span class="path" title="${escapeHtml(fileLoc)}">${escapeHtml(fileLoc)}</span>
            </td>
            <td>
              <div class="actions-mini">
                <button class="mbtn primary" data-act="open">Open</button>
                <button class="mbtn" data-act="copyjson">Copy JSON</button>
                <button class="mbtn" data-act="copypath">Copy path</button>
              </div>
            </td>
          </tr>
        `;
      }).join('');
    }

    const end = Math.min(view.length, start + pageSize);
    $('pagerInfo').textContent = `${view.length ? (start+1) : 0}-${end} / ${view.length} (page ${page+1}/${Math.max(1, Math.ceil(view.length / pageSize))})`;

    $('btnPrev').disabled = page <= 0;
    $('btnNext').disabled = (start + pageSize) >= view.length;
  }

  function openModal(x){
    const m = $('modal');
    const raw = x.raw || {};
    const sev = (x.severity||'').toUpperCase();
    $('mTitle').textContent = `${sev || 'INFO'} • ${x.title || 'Finding'}`;
    $('mSub').textContent = `${x.tool || '(tool?)'} • ${x.rule || '(id?)'} • ${x.fileLoc || ''}`;
    $('mJson').textContent = JSON.stringify(raw, null, 2);

    $('btnCopyJSON').onclick = ()=> copyText(JSON.stringify(raw, null, 2));
    $('btnClose').onclick = ()=> m.classList.add('hidden');
    $('modalClose').onclick = ()=> m.classList.add('hidden');

    m.classList.remove('hidden');
  }

  async function load(){
    banner('', false);
    $('rows').innerHTML = `<tr><td colspan="5" class="muted">Loading…</td></tr>`;
    try{
      const r = await fetch(API, { credentials:'same-origin' });
      const txt = await r.text();
      if (!r.ok) throw new Error(`HTTP ${r.status}: ${txt.slice(0,200)}`);

      let data = null;
      try { data = JSON.parse(txt); } catch(_){ data = null; }
      let items = [];
      if (Array.isArray(data)) items = data;
      else if (data && Array.isArray(data.items)) items = data.items;
      else if (data && Array.isArray(data.findings)) items = data.findings;
      else items = [];

      all = items.map(norm);
      buildToolOptions(all);
      $('kpiFetched').textContent = new Date().toLocaleString();

      apply();
      if (!all.length) banner('API returned 0 items. This is OK if no findings, but verify /api/vsp/findings source.', false);
    }catch(e){
      $('rows').innerHTML = `<tr><td colspan="5" class="muted">Failed to load.</td></tr>`;
      banner('Load failed: ' + (e && e.message ? e.message : String(e)), true);
      $('kpiFetched').textContent = '—';
    }
  }

  function bind(){
    $('btnReload').addEventListener('click', ()=>load());
    ['q','sev','tool','sort','pageSize'].forEach(id=>{
      $(id).addEventListener(id==='q' ? 'input' : 'change', ()=>apply());
    });
    $('btnPrev').addEventListener('click', ()=>{
      page = Math.max(0, page-1); render();
    });
    $('btnNext').addEventListener('click', ()=>{
      page = page+1; render();
    });

    $('rows').addEventListener('click', async (ev)=>{
      const btn = ev.target.closest('button');
      if (!btn) return;
      const tr = btn.closest('tr');
      const rid = parseInt(tr && tr.getAttribute('data-rid') || '-1', 10);
      const x = view[rid];
      if (!x) return;

      const act = btn.getAttribute('data-act');
      if (act === 'open') openModal(x);
      else if (act === 'copyjson') await copyText(JSON.stringify(x.raw||{}, null, 2));
      else if (act === 'copypath') await copyText(String(x.fileLoc||''));
    });
  }

  bind();
  load();
})();
JS
echo "[OK] wrote $JS"

# (4) patch Flask route /data (minimal, marker-based)
python3 - <<'PY'
import re
from pathlib import Path

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_DATA_SOURCE_TAB_P0_V1"

# Ensure render_template import exists (soft inject)
if "render_template" not in s:
    # Try extend "from flask import ..." line
    m = re.search(r"^from\s+flask\s+import\s+(.+)$", s, flags=re.M)
    if m:
        line = m.group(0)
        if "render_template" not in line:
            # add at end, keep commas
            newline = line.rstrip()
            if newline.endswith(")"):
                newline = newline[:-1]
                if not newline.endswith(","):
                    newline += ", "
                newline += "render_template)"
            else:
                if not newline.endswith(","):
                    newline += ", "
                newline += "render_template"
            s = s.replace(line, newline, 1)
    else:
        # insert standalone import near top
        s = "from flask import render_template\n" + s

if MARK not in s:
    block = f"""

# === {MARK} ===
@app.get("/data")
def vsp_data_source_tab_p0_v1():
    # Commercial Data Source tab (safe: purely reads via /api/vsp/findings on the client)
    return render_template("vsp_data_source_2025.html")
# === /{MARK} ===
"""
    # Insert before __main__ guard if present, else append
    mm = re.search(r"^if\s+__name__\s*==\s*['\\\"]__main__['\\\"]\s*:", s, flags=re.M)
    if mm:
        s = s[:mm.start()] + block + "\n" + s[mm.start():]
    else:
        s = s.rstrip() + "\n" + block + "\n"

APP.write_text(s, encoding="utf-8")
print("[OK] patched route /data into", APP)
PY

# (5) quick syntax checks
python3 -m py_compile "$APP"
echo "[OK] py_compile: $APP"

# node --check if available (optional)
if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: $JS" || echo "[WARN] node --check failed (non-fatal): $JS"
fi

echo
echo "[NEXT] restart UI then test:"
echo "  sudo systemctl restart vsp-ui-8910.service  ||  pkill -f 'gunicorn .*8910' ; (re)start your gunicorn"
echo "  curl -sS -I http://127.0.0.1:8910/data | head"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/findings | jq '.items|length? // length? // .items_len? // empty' -C"
