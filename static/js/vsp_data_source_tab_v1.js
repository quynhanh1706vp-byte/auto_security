(function(){
  'use strict';

  const API = '/api/vsp/findings';
  const $ = (id)=>document.getElementById(id);

  const sevRank = (s)=>{
    s = (s||'').toUpperCase();
    return ({CRITICAL:6,HIGH:5,MEDIUM:4,LOW:3,INFO:2, TRACE:1})[s] || 0;
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
