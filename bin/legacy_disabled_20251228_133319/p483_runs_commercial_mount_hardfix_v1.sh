#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p483_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_P483_COMMERCIAL_RUNS_MOUNT_HARDFIX_V1"
if TAG in s:
    print("[OK] P483 already present; no duplicate append")
    raise SystemExit(0)

patch = r"""
/* === VSP_P483_COMMERCIAL_RUNS_MOUNT_HARDFIX_V1 ===
   Purpose (commercial):
   - Always render Runs List into an independent mount (avoid being hidden by legacy-hide blocks)
   - Keep Scan/Start Run visible (commercial runner)
   - No DEMO overlay, no brittle dependency on legacy tables
*/
(function(){
  const TAG='[P483]';

  function log(){ try{ console.log(TAG, ...arguments);}catch(_e){} }
  function warn(){ try{ console.warn(TAG, ...arguments);}catch(_e){} }
  function qs(sel, root){ try{ return (root||document).querySelector(sel);}catch(_e){ return null; } }

  function createMount(){
    // mount must NOT be inside any legacy container that can be hidden
    let mount = qs('#vsp_runs_v3_mount', document);
    if (mount) return mount;

    mount = document.createElement('div');
    mount.id = 'vsp_runs_v3_mount';
    mount.style.cssText = [
      'max-width: 1200px',
      'margin: 16px auto',
      'padding: 12px',
      'border: 1px solid rgba(255,255,255,.08)',
      'border-radius: 14px',
      'background: rgba(0,0,0,.18)',
      'box-shadow: 0 10px 40px rgba(0,0,0,.25)',
      'position: relative',
      'z-index: 2'
    ].join(';');

    // try insert after the top header strip if exists, else at body top
    const headerCandidates = ['#vsp_top_strip', '#top_strip', '.vsp-top-strip', 'header', '#c_header'];
    let anchor = null;
    for (const sel of headerCandidates){
      const h = qs(sel, document);
      if (h && h.parentElement){ anchor = h; break; }
    }
    if (anchor && anchor.parentElement){
      anchor.parentElement.insertBefore(mount, anchor.nextSibling);
    } else {
      document.body.insertBefore(mount, document.body.firstChild);
    }
    return mount;
  }

  function el(tag, attrs, text){
    const e = document.createElement(tag);
    if (attrs){
      for (const k in attrs){
        const v = attrs[k];
        if (k === 'style') e.style.cssText = v;
        else if (k === 'class') e.className = v;
        else e.setAttribute(k, String(v));
      }
    }
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
  }

  function btn(label, onclick){
    const b = el('button', {style:[
      'padding: 6px 10px',
      'border-radius: 10px',
      'border: 1px solid rgba(255,255,255,.10)',
      'background: rgba(255,255,255,.06)',
      'color: #e8eefc',
      'cursor: pointer',
      'font-size: 12px'
    ].join(';')}, label);
    b.addEventListener('click', function(ev){ ev.preventDefault(); onclick && onclick(); });
    return b;
  }

  function th(txt){ return el('th', {style:'text-align:left; padding:8px; border-bottom:1px solid rgba(255,255,255,.08); font-weight:600; color:rgba(240,245,255,.9);'}, txt); }
  function td(txt){
    const cell = el('td', {style:'padding:8px; border-bottom:1px solid rgba(255,255,255,.06); color:rgba(235,240,255,.88); vertical-align:top;'});
    if (txt instanceof Node) cell.appendChild(txt);
    else cell.textContent = (txt===undefined||txt===null) ? '' : String(txt);
    return cell;
  }

  async function fetchJson(url){
    const r = await fetch(url, {credentials:'same-origin'});
    if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + url);
    return await r.json();
  }

  async function fetchRuns(){
    // prefer v3; fallback to legacy
    const tries = [
      '/api/vsp/runs_v3?limit=250&include_ci=1',
      '/api/vsp/runs_v3?limit=250',
      '/api/vsp/runs?limit=250&offset=0'
    ];
    let lastErr = null;
    for (const u of tries){
      try{
        const j = await fetchJson(u);
        const items = j.items || j.data || j.runs || [];
        return {src:u, items: Array.isArray(items) ? items : []};
      }catch(e){
        lastErr = e;
      }
    }
    throw lastErr || new Error('no runs api available');
  }

  function getRid(it){
    return it.rid || it.run_id || it.id || it.RID || '';
  }
  function getOverall(it){
    return it.overall || it.status || it.verdict || it.gate || it.result || '';
  }
  function getTs(it){
    return it.ts || it.time || it.created_at || it.created || it.date || '';
  }

  function linkMaybe(text, href){
    if (!href) return el('span', {style:'opacity:.6'}, text);
    const a = el('a', {href: href, target:'_blank', style:'color:#b7cffd; text-decoration:none;'}, text);
    a.addEventListener('mouseover', ()=>a.style.textDecoration='underline');
    a.addEventListener('mouseout', ()=>a.style.textDecoration='none');
    return a;
  }

  function deriveLinks(it, rid){
    // be conservative: only use if present; otherwise keep blank
    const links = it.links || it.artifacts || it.urls || {};
    const csv  = links.csv  || it.csv_url  || it.csv || '';
    const html = links.html || it.html_url || it.html || '';
    const sarif= links.sarif|| it.sarif_url|| it.sarif|| '';
    const sum  = links.summary || it.summary_url || it.summary || '';
    // optional generic open
    const open = it.open_url || (rid ? ('/c/data_source?rid=' + encodeURIComponent(rid)) : '');
    return {csv, html, sarif, sum, open};
  }

  function forceUnhideCommercialControls(){
    // If legacy-hide accidentally hid the scan form, bring it back (commercial needs it).
    // Do this gently and only a few rounds.
    const texts = ['Scan / Start Run', 'Target path', 'Start scan', 'Refresh status'];
    const nodes = Array.prototype.slice.call(document.querySelectorAll('section,div,article,form'), 0, 1200);
    for (const n of nodes){
      try{
        const t = (n.textContent || '').trim();
        if (!t) continue;
        for (const key of texts){
          if (t.includes(key)){
            n.style.display = '';
            n.hidden = false;
            n.classList.remove('hidden','vsp-hidden','vsp_legacy_hidden','vsp-legacy-hidden');
          }
        }
      }catch(_e){}
    }
  }

  function renderBox(mount, title, rightNode){
    const top = el('div', {style:'display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:10px;'});
    const h = el('div', {style:'font-size:13px; font-weight:700; color:rgba(240,245,255,.92);'}, title);
    top.appendChild(h);
    if (rightNode) top.appendChild(rightNode);
    mount.appendChild(top);
  }

  function renderRuns(mount, src, items){
    mount.innerHTML = '';

    const right = el('div', {style:'display:flex; gap:8px; align-items:center;'});
    right.appendChild(el('span', {style:'font-size:12px; opacity:.75;'}, 'src: ' + src));
    right.appendChild(btn('Refresh', ()=>boot(true)));
    renderBox(mount, 'Runs & Reports (commercial list)', right);

    if (!items || !items.length){
      const empty = el('div', {style:'padding:10px; border:1px dashed rgba(255,255,255,.14); border-radius:12px; opacity:.85;'}, 'No runs yet. Use “Scan / Start Run” below to create your first run.');
      mount.appendChild(empty);
      return;
    }

    const wrap = el('div', {style:'overflow:auto; border:1px solid rgba(255,255,255,.06); border-radius:12px;'});
    const table = el('table', {style:'width:100%; border-collapse:collapse; font-size:12px;'});
    const thead = el('thead');
    const trh = el('tr');
    ['RID','OVERALL','TS','CSV','HTML','SARIF','SUMMARY','OPEN'].forEach(x=>trh.appendChild(th(x)));
    thead.appendChild(trh);
    table.appendChild(thead);

    const tbody = el('tbody');
    const max = Math.min(items.length, 250);
    for (let i=0;i<max;i++){
      const it = items[i] || {};
      const rid = getRid(it);
      const overall = getOverall(it);
      const ts = getTs(it);
      const L = deriveLinks(it, rid);

      const tr = el('tr');
      tr.appendChild(td(rid || '(none)'));
      tr.appendChild(td(overall || ''));
      tr.appendChild(td(ts || ''));
      tr.appendChild(td(linkMaybe('csv', L.csv)));
      tr.appendChild(td(linkMaybe('html', L.html)));
      tr.appendChild(td(linkMaybe('sarif', L.sarif)));
      tr.appendChild(td(linkMaybe('summary', L.sum)));
      tr.appendChild(td(linkMaybe('open', L.open)));
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);
    wrap.appendChild(table);
    mount.appendChild(wrap);

    mount.appendChild(el('div', {style:'margin-top:8px; font-size:12px; opacity:.7;'},
      'Showing ' + Math.min(items.length,250) + '/' + items.length + ' items.'));

    // after we successfully render, keep commercial controls visible
    forceUnhideCommercialControls();
  }

  let _booting = false;
  async function boot(force){
    if (_booting && !force) return;
    _booting = true;
    try{
      // kill any old overlays if exist
      document.querySelectorAll('#vsp_runs_overlay,.vsp-runs-overlay').forEach(e=>{ try{ e.remove(); }catch(_e){} });

      const mount = createMount();
      renderBox(mount, 'Runs & Reports (loading...)', null);

      // fight legacy-hide for a short window (commercial stability)
      let tries = 0;
      const t = setInterval(()=>{ tries++; forceUnhideCommercialControls(); if (tries>=12) clearInterval(t); }, 250);

      const r = await fetchRuns();
      log('runs fetched items=', r.items.length, 'src=', r.src);
      renderRuns(mount, r.src, r.items);
    }catch(e){
      warn('boot failed:', e);
      const mount = createMount();
      mount.innerHTML = '';
      renderBox(mount, 'Runs & Reports (error)', btn('Retry', ()=>boot(true)));
      mount.appendChild(el('pre', {style:'white-space:pre-wrap; opacity:.85; font-size:12px; padding:10px; border:1px solid rgba(255,255,255,.08); border-radius:12px;'},
        String(e && (e.stack||e.message||e))));
      forceUnhideCommercialControls();
    }finally{
      _booting = false;
    }
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', ()=>boot(false));
  } else {
    boot(false);
  }
})();
"""
p.write_text(s + "\n\n" + patch + "\n", encoding="utf-8")
print("[OK] appended P483 commercial mount hardfix")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" | tee -a "$OUT/log.txt"
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
else
  echo "[WARN] node not found; skip node --check" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P483 done." | tee -a "$OUT/log.txt"
echo "[NEXT] Close ALL /c/runs tabs, reopen http://127.0.0.1:8910/c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[LOG] $OUT/log.txt" | tee -a "$OUT/log.txt"
