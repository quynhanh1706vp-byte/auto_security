#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need sudo; need systemctl; need curl; need date; need mkdir

F="static/js/vsp_dashboard_luxe_v1.js"
mkdir -p "$(dirname "$F")"
[ -f "$F" ] && cp -f "$F" "${F}.bak_p56f_${TS}"

cat > "$F" <<'JS'
/* VSP Dashboard Luxe SAFE (P56F) - crash-free minimal dashboard renderer */
(function(){
  'use strict';

  const log = (...a)=>{ try{ console.log('[VSP][dash]', ...a); }catch(_e){} };
  const qs  = (s, r=document)=>r.querySelector(s);

  function getRID(){
    try { return new URL(location.href).searchParams.get('rid') || ''; }
    catch(e){ return ''; }
  }

  function host(){
    return (
      qs('#vsp_dashboard_root') ||
      qs('#vsp5_root') ||
      qs('#vsp_content') ||
      qs('main') ||
      document.body
    );
  }

  function esc(s){
    return String(s ?? '')
      .replaceAll('&','&amp;')
      .replaceAll('<','&lt;')
      .replaceAll('>','&gt;')
      .replaceAll('"','&quot;')
      .replaceAll("'",'&#39;');
  }

  function fmt(n){
    const x = Number(n||0);
    return Number.isFinite(x) ? x.toLocaleString() : '0';
  }

  function classify(sev){
    const s = String(sev||'').toUpperCase();
    if(s.includes('CRIT')) return 'crit';
    if(s.includes('HIGH')) return 'high';
    if(s.includes('MED'))  return 'med';
    if(s.includes('LOW'))  return 'low';
    if(s.includes('INFO')) return 'info';
    if(s.includes('TRACE'))return 'trace';
    return 'unk';
  }

  async function fetchJson(url, timeoutMs=12000){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: ctrl.signal, headers: {'Accept':'application/json'}});
      const txt = await r.text();
      let j = null;
      try{ j = JSON.parse(txt); }catch(_e){ j = null; }
      return { ok: r.ok, status: r.status, json: j, text: txt };
    } finally {
      clearTimeout(t);
    }
  }

  function renderSkeleton(root){
    const rid = getRID();
    root.innerHTML = `
      <div class="vsp-p56f-wrap" style="padding:18px;">
        <div style="display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:14px;">
          <div>
            <div style="font-size:18px; font-weight:700; letter-spacing:.2px;">VSP • Dashboard</div>
            <div style="opacity:.75; margin-top:4px; font-size:12px;">SAFE mode (P56F) — prevents JS crash, shows data if API available.</div>
          </div>
          <div style="display:flex; gap:8px; align-items:center;">
            <div style="opacity:.85; font-size:12px;">RID: <code>${esc(rid || '(none)')}</code></div>
            <button id="p56f_reload" style="padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background:rgba(255,255,255,.06); color:inherit; cursor:pointer;">Reload</button>
          </div>
        </div>

        <div id="p56f_status" style="margin:10px 0; padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.12);">
          Loading…
        </div>

        <div id="p56f_kpis" style="display:grid; grid-template-columns: repeat(6, minmax(0,1fr)); gap:10px; margin:12px 0;"></div>

        <div style="margin-top:14px; border:1px solid rgba(255,255,255,.10); border-radius:14px; overflow:hidden;">
          <div style="padding:10px 12px; border-bottom:1px solid rgba(255,255,255,.08); font-weight:600;">Top Findings</div>
          <div style="overflow:auto;">
            <table style="width:100%; border-collapse:collapse; font-size:12px;">
              <thead style="opacity:.85;">
                <tr>
                  <th style="text-align:left; padding:8px 10px; border-bottom:1px solid rgba(255,255,255,.08);">Sev</th>
                  <th style="text-align:left; padding:8px 10px; border-bottom:1px solid rgba(255,255,255,.08);">Tool</th>
                  <th style="text-align:left; padding:8px 10px; border-bottom:1px solid rgba(255,255,255,.08);">Rule</th>
                  <th style="text-align:left; padding:8px 10px; border-bottom:1px solid rgba(255,255,255,.08);">File:Line</th>
                  <th style="text-align:left; padding:8px 10px; border-bottom:1px solid rgba(255,255,255,.08);">Message</th>
                </tr>
              </thead>
              <tbody id="p56f_tbl"></tbody>
            </table>
          </div>
        </div>
      </div>
    `;
    const btn = qs('#p56f_reload');
    if(btn) btn.addEventListener('click', ()=>init(true));
  }

  function renderKpis(counts){
    const order = ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'];
    const wrap = qs('#p56f_kpis');
    if(!wrap) return;
    wrap.innerHTML = order.map(k=>{
      const v = counts[k] || 0;
      return `
        <div style="padding:10px 12px; border-radius:14px; border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.10);">
          <div style="opacity:.8; font-size:11px;">${k}</div>
          <div style="font-size:20px; font-weight:800; margin-top:4px;">${fmt(v)}</div>
        </div>
      `;
    }).join('');
  }

  function renderTable(items){
    const tb = qs('#p56f_tbl');
    if(!tb) return;
    tb.innerHTML = (items||[]).slice(0,200).map(it=>{
      const sev = esc(it.severity || it.sev || 'UNKNOWN');
      const tool = esc(it.tool || '');
      const rule = esc(it.rule || it.check_id || it.id || '');
      const file = esc(it.file || it.path || '');
      const line = esc(it.line || it.start_line || '');
      const msg  = esc(it.message || it.msg || it.title || '');
      const cls = classify(sev);
      return `
        <tr>
          <td style="padding:7px 10px; border-bottom:1px solid rgba(255,255,255,.06);"><span class="p56f-sev ${cls}" style="padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.10);">${sev}</span></td>
          <td style="padding:7px 10px; border-bottom:1px solid rgba(255,255,255,.06);">${tool}</td>
          <td style="padding:7px 10px; border-bottom:1px solid rgba(255,255,255,.06);">${rule}</td>
          <td style="padding:7px 10px; border-bottom:1px solid rgba(255,255,255,.06);"><code>${file}${line?':'+line:''}</code></td>
          <td style="padding:7px 10px; border-bottom:1px solid rgba(255,255,255,.06);">${msg}</td>
        </tr>
      `;
    }).join('');
  }

  function setStatus(html){
    const st = qs('#p56f_status');
    if(st) st.innerHTML = html;
  }

  async function init(force){
    const root = host();
    if(!root) return;
    renderSkeleton(root);

    const rid = getRID();
    const q = rid ? ('&rid='+encodeURIComponent(rid)) : '';
    const url = '/api/vsp/top_findings_v2?limit=200' + q;

    setStatus(`Loading <code>${esc(url)}</code> …`);
    const r = await fetchJson(url, 15000);

    if(!r.ok || !r.json || r.json.ok === false){
      setStatus(`<b style="color:#ffb3b3;">Failed to load findings</b><div style="opacity:.8; margin-top:6px;">HTTP ${r.status}. Open DevTools → Network/Console.</div>`);
      renderKpis({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0});
      renderTable([]);
      return;
    }

    const items = Array.isArray(r.json.items) ? r.json.items : [];
    const counts = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
    for(const it of items){
      const s = String(it.severity || it.sev || '').toUpperCase();
      if(s.includes('CRIT')) counts.CRITICAL++;
      else if(s.includes('HIGH')) counts.HIGH++;
      else if(s.includes('MED')) counts.MEDIUM++;
      else if(s.includes('LOW')) counts.LOW++;
      else if(s.includes('INFO')) counts.INFO++;
      else if(s.includes('TRACE')) counts.TRACE++;
    }

    setStatus(`<b style="color:#b9ffcc;">OK</b> • items=${fmt(items.length)} • rid=<code>${esc(rid||'(none)')}</code>`);
    renderKpis(counts);
    renderTable(items);
    log('loaded', {items: items.length, rid});
  }

  try{
    if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ()=>init(false));
    else init(false);
  }catch(e){
    try{ console.error('[VSP][dash] fatal', e); }catch(_e){}
  }
})();
JS

echo "== [P56F] node --check =="
node --check "$F"

echo "== [P56F] restart service =="
sudo systemctl restart "$SVC"

echo "== [P56F] wait /vsp5 200 (max 30s) =="
ok=0
for i in $(seq 1 30); do
  code="$(curl -fsS --connect-timeout 1 --max-time 2 -o /dev/null -w "%{http_code}" "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done
[ "$ok" = "1" ] || { echo "[ERR] /vsp5 not 200 after restart"; exit 2; }

echo "[DONE] P56F applied. IMPORTANT: Hard refresh browser (Ctrl+Shift+R)."
