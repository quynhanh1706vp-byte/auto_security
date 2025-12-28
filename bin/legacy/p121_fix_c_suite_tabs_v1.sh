#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "${f}.bak_p121_${TS}"
  ok "backup: ${f}.bak_p121_${TS}"
}

write(){
  local f="$1"; shift
  backup "$f"
  cat > "$f" <<'JS'
/* P121 - generated */
JS
  cat >> "$f" <<<"$*"
  ok "wrote: $f"
}

# ------------------------
# shared mini helpers (embedded per file to avoid dependency mismatch)
# ------------------------
COMMON_HELPERS='
(function(){
  "use strict";
  const W = window;
  const log = (...a)=>console.log("[VSPC]", ...a);
  const warn = (...a)=>console.warn("[VSPC]", ...a);

  function qs(sel, root=document){ return root.querySelector(sel); }
  function qsa(sel, root=document){ return Array.from(root.querySelectorAll(sel)); }

  function text(el, s){ if(!el) return; el.textContent = (s==null?"":String(s)); }

  function sanitizeRid(r){
    r = (r==null?"":String(r)).trim();
    // allow typical RID chars only
    r = r.replace(/[^\w\-:.]/g, "");
    if (r.length>160) r = r.slice(0,160);
    return r;
  }

  function getParam(name){
    try { return new URLSearchParams(location.search).get(name) || ""; }
    catch(e){ return ""; }
  }

  function getRid(){
    const u = sanitizeRid(getParam("rid"));
    const ls = sanitizeRid(localStorage.getItem("VSP_C_RID")||"");
    return u || ls || "";
  }
  function setRid(rid){
    rid = sanitizeRid(rid);
    if (rid) localStorage.setItem("VSP_C_RID", rid);
    return rid;
  }

  async function fetchJSON(url, opt={}){
    const to = opt.timeout_ms || 8000;
    const ctl = new AbortController();
    const t = setTimeout(()=>ctl.abort(), to);
    try{
      const r = await fetch(url, {signal: ctl.signal, cache:"no-store", credentials:"same-origin"});
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      const body = await r.text();
      let j = null;
      if (ct.includes("application/json")) {
        try { j = JSON.parse(body); } catch(e){ j=null; }
      } else {
        try { j = JSON.parse(body); } catch(e){ j=null; }
      }
      return {ok:r.ok, status:r.status, json:j, text:body, url};
    } finally { clearTimeout(t); }
  }

  async function firstOK(urls){
    for (const u of urls){
      const res = await fetchJSON(u, {timeout_ms: 9000});
      if (res.ok && res.json) return res;
    }
    return null;
  }

  // expose minimal bus (optional)
  W.VSP_C = W.VSP_C || {};
  W.VSP_C.p121 = {qs,qsa,text,log,warn,sanitizeRid,getParam,getRid,setRid,fetchJSON,firstOK};
})();
'

# ------------------------
# /c/runs
# ------------------------
write "static/js/vsp_c_runs_v1.js" "${COMMON_HELPERS}
(function(){
  'use strict';
  const H = window.VSP_C && window.VSP_C.p121;
  if(!H){ console.warn('[VSPC] missing helpers'); return; }
  const {qs,qsa,text,log,warn,getRid,setRid,firstOK,sanitizeRid} = H;

  function findRunsTable(){
    const tables = qsa('table');
    for(const t of tables){
      const th = t.querySelectorAll('th');
      const head = Array.from(th).map(x=>x.textContent.trim().toLowerCase()).join('|');
      if(head.includes('rid') && head.includes('action')) return t;
      // fallback: the panel table usually has 3 cols and 'runs' text nearby
    }
    return qs('#runs_table') || qs('table');
  }

  function renderRows(tbody, items){
    tbody.innerHTML = '';
    for(const it of items){
      const rid = sanitizeRid(it.rid || it.run_id || it.id || '');
      const label = (it.label || it.ts || it.time || it.when || '').toString();
      const verdict = (it.verdict || it.status || '').toString();
      const tr = document.createElement('tr');

      const tdRid = document.createElement('td');
      tdRid.textContent = rid || '(none)';
      tdRid.style.whiteSpace='nowrap';

      const tdLabel = document.createElement('td');
      tdLabel.textContent = label || '';

      const tdAct = document.createElement('td');
      tdAct.style.whiteSpace='nowrap';
      const dash = document.createElement('a');
      dash.href = '/c/dashboard?rid=' + encodeURIComponent(rid);
      dash.textContent = 'Dashboard';
      dash.style.marginRight='10px';

      const csv = document.createElement('a');
      csv.href = '/api/vsp/export_findings_csv_v1?rid=' + encodeURIComponent(rid);
      csv.textContent = 'CSV';
      csv.style.marginRight='10px';

      const rep = document.createElement('a');
      rep.href = '/api/vsp/export_reports_tgz_v1?rid=' + encodeURIComponent(rid);
      rep.textContent = 'Reports.tgz';
      rep.style.marginRight='10px';

      const pick = document.createElement('button');
      pick.textContent = 'Use RID';
      pick.style.marginLeft='6px';
      pick.onclick = ()=>{ setRid(rid); location.href = '/c/runs?rid=' + encodeURIComponent(rid); };

      tdAct.appendChild(dash);
      tdAct.appendChild(csv);
      tdAct.appendChild(rep);
      if (verdict) {
        const sp = document.createElement('span');
        sp.textContent = verdict;
        sp.style.opacity='0.75';
        sp.style.marginLeft='8px';
        tdAct.appendChild(sp);
      }
      if (rid) tdAct.appendChild(pick);

      tr.appendChild(tdRid);
      tr.appendChild(tdLabel);
      tr.appendChild(tdAct);
      tbody.appendChild(tr);
    }
  }

  async function main(){
    const rid = getRid();
    if (rid) log('runs rid=', rid);

    const tbl = findRunsTable();
    if(!tbl){ warn('runs: table not found'); return; }
    let tb = tbl.querySelector('tbody');
    if(!tb){ tb = document.createElement('tbody'); tbl.appendChild(tb); }

    // find filter input
    const inp = qsa('input').find(x=>(x.placeholder||'').toLowerCase().includes('filter')) || null;

    tb.innerHTML = '<tr><td colspan=\"3\" style=\"opacity:.7\">Loading...</td></tr>';

    const res = await firstOK([
      '/api/ui/runs_v3?limit=200&include_ci=1',
      '/api/vsp/runs_v3?limit=200&include_ci=1',
      '/api/vsp/runs_v2?limit=200'
    ]);

    if(!res){
      tb.innerHTML = '<tr><td colspan=\"3\" style=\"color:#ffb\">Cannot load runs API</td></tr>';
      return;
    }

    const items = (res.json.items || res.json.data || res.json.runs || []);
    const norm = items.map(x=>({
      rid: x.rid || x.run_id || x.id,
      label: x.label || x.ts || x.when || x.created_at || '',
      verdict: x.verdict || x.overall || x.status || ''
    }));

    let view = norm;
    renderRows(tb, view);

    if(inp){
      inp.addEventListener('input', ()=>{
        const q = (inp.value||'').toLowerCase().trim();
        if(!q){ view = norm; renderRows(tb, view); return; }
        view = norm.filter(x=>(x.rid||'').toLowerCase().includes(q) || (x.label||'').toLowerCase().includes(q));
        renderRows(tb, view);
      });
    }
  }

  window.addEventListener('DOMContentLoaded', ()=>{ main().catch(e=>console.error(e)); });
})();
"

# ------------------------
# /c/data_source
# ------------------------
write "static/js/vsp_c_data_source_v1.js" "${COMMON_HELPERS}
(function(){
  'use strict';
  const H = window.VSP_C && window.VSP_C.p121;
  if(!H){ console.warn('[VSPC] missing helpers'); return; }
  const {qs,qsa,log,warn,getRid,firstOK} = H;

  function findDataTable(){
    // prefer the big preview table (many columns)
    const tables = qsa('table');
    let best = null, bestScore = -1;
    for(const t of tables){
      const th = Array.from(t.querySelectorAll('th')).map(x=>x.textContent.trim().toLowerCase());
      const score =
        (th.includes('severity')?2:0) +
        (th.includes('title')?2:0) +
        (th.includes('tool')?1:0) +
        (th.includes('location')?1:0) +
        (th.length>=6?1:0);
      if(score>bestScore){ best=t; bestScore=score; }
    }
    return best || qs('table');
  }

  function cell(s){
    const td=document.createElement('td');
    td.textContent = (s==null?'':String(s));
    return td;
  }

  function render(tbody, rows){
    tbody.innerHTML='';
    for(const r of rows){
      const tr=document.createElement('tr');
      tr.appendChild(cell(r.id||''));
      tr.appendChild(cell(r.tool||''));
      tr.appendChild(cell(r.type||''));
      tr.appendChild(cell(r.severity||''));
      tr.appendChild(cell(r.title||''));
      tr.appendChild(cell(r.component||''));
      tr.appendChild(cell(r.version||''));
      tr.appendChild(cell(r.location||''));
      tr.appendChild(cell(r.fix||''));
      tbody.appendChild(tr);
    }
  }

  async function main(){
    const rid = getRid();
    const tbl = findDataTable();
    if(!tbl){ warn('data_source: table not found'); return; }
    let tb = tbl.querySelector('tbody');
    if(!tb){ tb=document.createElement('tbody'); tbl.appendChild(tb); }

    let offset = 0;
    const limit = 200;

    async function load(){
      tb.innerHTML = '<tr><td colspan=\"12\" style=\"opacity:.7\">Loading...</td></tr>';

      const r = encodeURIComponent(rid||'');
      const res = await firstOK([
        `/api/vsp/datasource_v3?rid=${r}&limit=${limit}&offset=${offset}`,
        `/api/vsp/datasource?rid=${r}&limit=${limit}&offset=${offset}`,
        `/api/vsp/findings_unified_v1?rid=${r}&limit=${limit}&offset=${offset}`,
        `/api/vsp/data_source_v1?rid=${r}&limit=${limit}&offset=${offset}`
      ]);

      if(!res){
        tb.innerHTML = '<tr><td colspan=\"12\" style=\"color:#ffb\">Cannot load datasource API</td></tr>';
        return;
      }
      const j = res.json;
      const rows = (j.items || j.rows || j.data || []);
      render(tb, rows);
      log('data_source rows=', rows.length, 'offset=', offset);
    }

    // hook next button if exists
    const nextBtn = qsa('button').find(b=>(b.textContent||'').toLowerCase().includes('next')) || null;
    if(nextBtn){
      nextBtn.onclick = ()=>{ offset += limit; load().catch(console.error); };
    }

    await load();
  }

  window.addEventListener('DOMContentLoaded', ()=>{ main().catch(e=>console.error(e)); });
})();
"

# ------------------------
# /c/settings
# ------------------------
write "static/js/vsp_c_settings_v1.js" "${COMMON_HELPERS}
(function(){
  'use strict';
  const H = window.VSP_C && window.VSP_C.p121;
  if(!H){ console.warn('[VSPC] missing helpers'); return; }
  const {qs,qsa,log,warn,getRid,fetchJSON,firstOK} = H;

  function findProbeTable(){
    const tables = qsa('table');
    for(const t of tables){
      const th = Array.from(t.querySelectorAll('th')).map(x=>x.textContent.trim().toLowerCase()).join('|');
      if(th.includes('endpoint') || th.includes('status')) return t;
    }
    return null;
  }

  async function main(){
    const rid = getRid();
    const pre = qsa('pre').find(x=>(x.textContent||'').includes('{')) || null;

    const probes = [
      {name:'runs_v3', url:'/api/ui/runs_v3?limit=1&include_ci=1'},
      {name:'dashboard_kpis_v4', url:'/api/vsp/dashboard_kpis_v4' + (rid?('?rid='+encodeURIComponent(rid)):'')},
      {name:'top_findings_v2', url:'/api/vsp/top_findings_v2?limit=1' + (rid?('&rid='+encodeURIComponent(rid)):'')},
      {name:'trend_v1', url:'/api/vsp/trend_v1'}
    ];

    // render probes
    const t = findProbeTable();
    if(t){
      let tb = t.querySelector('tbody'); if(!tb){ tb=document.createElement('tbody'); t.appendChild(tb); }
      tb.innerHTML='';
      for(const p of probes){
        const tr=document.createElement('tr');
        tr.innerHTML = `<td style=\"white-space:nowrap\">${p.name}</td><td style=\"opacity:.7\">Loading...</td>`;
        tb.appendChild(tr);
        const res = await fetchJSON(p.url, {timeout_ms:7000});
        tr.children[1].textContent = res.ok ? `OK (${res.status})` : `FAIL (${res.status})`;
      }
    }

    // show a compact settings JSON in <pre> if present (don’t crash if missing endpoint)
    if(pre){
      const res = await firstOK([
        '/api/vsp/settings_v1',
        '/api/vsp/policy_v1',
        '/api/vsp/config_v1'
      ]);
      if(res && res.json){
        pre.textContent = JSON.stringify(res.json, null, 2);
      }
    }

    log('settings ok rid=', rid||'(none)');
  }

  window.addEventListener('DOMContentLoaded', ()=>{ main().catch(e=>console.error(e)); });
})();
"

# ------------------------
# /c/rule_overrides
# ------------------------
write "static/js/vsp_c_rule_overrides_v1.js" "${COMMON_HELPERS}
(function(){
  'use strict';
  const H = window.VSP_C && window.VSP_C.p121;
  if(!H){ console.warn('[VSPC] missing helpers'); return; }
  const {qs,qsa,log,warn,fetchJSON,firstOK} = H;

  function findEditor(){
    return qs('textarea') || qs('#rule_overrides_editor') || null;
  }

  function findBtn(label){
    const L = label.toLowerCase();
    return qsa('button').find(b=>(b.textContent||'').trim().toLowerCase()===L) || null;
  }

  async function loadBackend(){
    const res = await firstOK([
      '/api/vsp/rule_overrides_v1',
      '/api/vsp/rule_overrides',
      '/api/vsp/overrides_v1'
    ]);
    return res && res.json ? res.json : null;
  }

  async function main(){
    const ed = findEditor();
    if(!ed){ warn('rule_overrides: textarea not found'); return; }

    const key = 'vsp_rule_overrides_v1';

    async function doLoad(){
      const j = await loadBackend();
      if(j){
        ed.value = JSON.stringify(j, null, 2);
        localStorage.setItem(key, ed.value);
        log('rule_overrides loaded from backend');
      } else {
        const s = localStorage.getItem(key) || '{\"ok\":false,\"items\":[]}';
        ed.value = s;
        log('rule_overrides loaded from localStorage');
      }
    }

    async function doSave(){
      let obj=null;
      try{ obj=JSON.parse(ed.value); }catch(e){ alert('JSON invalid'); return; }

      // best-effort POST (if backend supports)
      try{
        const r = await fetch('/api/vsp/rule_overrides_v1', {
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body: JSON.stringify(obj),
          cache:'no-store',
          credentials:'same-origin'
        });
        if(r.ok){
          localStorage.setItem(key, ed.value);
          alert('Saved (backend)');
          return;
        }
      } catch(e){ /* ignore */ }

      // fallback
      localStorage.setItem(key, ed.value);
      alert('Saved (local)');
    }

    async function doExport(){
      const blob = new Blob([ed.value], {type:'application/json'});
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'rule_overrides.json';
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 500);
    }

    const bLoad = findBtn('LOAD') || findBtn('Load');
    const bSave = findBtn('SAVE') || findBtn('Save');
    const bExp  = findBtn('EXPORT') || findBtn('Export');

    if(bLoad) bLoad.onclick = ()=>doLoad().catch(console.error);
    if(bSave) bSave.onclick = ()=>doSave().catch(console.error);
    if(bExp)  bExp.onclick  = ()=>doExport();

    await doLoad();
  }

  window.addEventListener('DOMContentLoaded', ()=>{ main().catch(e=>console.error(e)); });
})();
"

ok "P121 applied."
echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/data_source"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
