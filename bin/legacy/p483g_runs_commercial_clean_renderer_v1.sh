#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p483g_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p483g_${TS}"
echo "[OK] backup => ${F}.bak_p483g_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")

js = r"""
/* VSP Commercial - Runs renderer (clean & resilient)
 * P483g: Fix flicker/blank by robust data fallback + stable mount + no legacy fight
 * - Prefer runs_v3 when it has items
 * - If runs_v3 returns items:0, fallback to runs v1 (offset-based)
 * - Render independent list UI into a stable root
 */
(function(){
  'use strict';
  const TAG = '[P483g]';
  const ROOT_ID = 'vsp_runs_commercial_root_v1';
  const CSS_ID  = 'vsp_runs_commercial_css_v1';

  const log = (...a)=>{ try{ console.log(TAG, ...a); }catch(e){} };
  const warn= (...a)=>{ try{ console.warn(TAG, ...a); }catch(e){} };

  function esc(s){
    return String(s ?? '').replace(/[&<>"']/g, m => ({
      '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
    }[m]));
  }

  function injectCss(){
    if (document.getElementById(CSS_ID)) return;
    const st = document.createElement('style');
    st.id = CSS_ID;
    st.textContent = `
      #${ROOT_ID}{ max-width: 1180px; margin: 18px auto 26px auto; padding: 0 10px; }
      #${ROOT_ID} .vsp_card{ background: rgba(20,24,34,.55); border:1px solid rgba(255,255,255,.08); border-radius: 14px; box-shadow: 0 10px 30px rgba(0,0,0,.35); overflow:hidden; }
      #${ROOT_ID} .vsp_card_hd{ padding: 12px 14px; display:flex; align-items:center; justify-content:space-between; gap:10px; border-bottom:1px solid rgba(255,255,255,.08); }
      #${ROOT_ID} .vsp_card_hd .t{ font-weight: 700; letter-spacing:.2px; opacity:.95; }
      #${ROOT_ID} .vsp_card_hd .sub{ font-size:12px; opacity:.75; }
      #${ROOT_ID} .vsp_row{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      #${ROOT_ID} .chip{ font-size:12px; padding:4px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.10); background: rgba(255,255,255,.04); cursor:pointer; user-select:none; }
      #${ROOT_ID} .chip.on{ background: rgba(120,160,255,.16); border-color: rgba(120,160,255,.35); }
      #${ROOT_ID} input, #${ROOT_ID} select{
        background: rgba(0,0,0,.22); border:1px solid rgba(255,255,255,.10);
        color: inherit; border-radius: 10px; padding: 7px 9px; outline:none;
      }
      #${ROOT_ID} .btn{
        background: rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.10);
        padding:6px 10px; border-radius: 10px; cursor:pointer; font-size:12px;
      }
      #${ROOT_ID} .btn:hover{ background: rgba(255,255,255,.10); }
      #${ROOT_ID} .meta{ font-size:12px; opacity:.75; }
      #${ROOT_ID} table{ width:100%; border-collapse: collapse; }
      #${ROOT_ID} th, #${ROOT_ID} td{ padding: 9px 10px; border-bottom:1px solid rgba(255,255,255,.06); font-size:12px; }
      #${ROOT_ID} th{ text-align:left; opacity:.75; font-weight:700; }
      #${ROOT_ID} .st{ font-weight:700; }
      #${ROOT_ID} .st.OK{ color: #a8ffb0; }
      #${ROOT_ID} .st.WARN{ color: #ffd48a; }
      #${ROOT_ID} .st.FAIL{ color: #ff9aa8; }
      #${ROOT_ID} .st.UNKNOWN{ color: #b9c2d6; }
      #${ROOT_ID} .links a{ margin-right: 8px; text-decoration:none; opacity:.9; }
      #${ROOT_ID} .links a:hover{ text-decoration: underline; opacity:1; }
      #${ROOT_ID} .empty{ padding: 12px 14px; opacity:.75; }
    `;
    document.head.appendChild(st);
  }

  function ensureRoot(){
    let root = document.getElementById(ROOT_ID);
    if (root) return root;

    root = document.createElement('div');
    root.id = ROOT_ID;
    root.dataset.vspKeep = '1';

    // Try to insert near top of main content if possible, otherwise body.
    const anchor =
      document.querySelector('#vsp_p471b_root') ||
      document.querySelector('[id*="vsp_"][id*="_root"]') ||
      document.body;

    if (anchor === document.body) {
      document.body.insertBefore(root, document.body.firstChild);
    } else {
      anchor.insertBefore(root, anchor.firstChild);
    }

    return root;
  }

  function classifyStatus(overall){
    const s = String(overall ?? '').toUpperCase();
    if (s.includes('PASS') || s === 'OK' || s.includes('GREEN')) return 'OK';
    if (s.includes('WARN') || s.includes('AMBER')) return 'WARN';
    if (s.includes('FAIL') || s.includes('RED') || s.includes('ERROR')) return 'FAIL';
    return 'UNKNOWN';
  }

  async function fetchJson(url){
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP '+r.status);
    return await r.json();
  }

  async function fetchRuns(){
    // IMPORTANT: runs_v3 may return items:0 (your screenshot). We treat that as "try next".
    const candidates = [
      '/api/vsp/runs_v3?limit=250&include_ci=1',
      '/api/vsp/runs?limit=250&offset=0&include_ci=1',
      '/api/vsp/runs?limit=250&offset=0',
      '/api/ui/runs_v3?limit=250&include_ci=1',
    ];

    let bestEmpty = null;

    for (const url of candidates){
      try{
        const j = await fetchJson(url);
        const items = Array.isArray(j?.items) ? j.items : (Array.isArray(j?.runs) ? j.runs : []);
        if (items.length > 0){
          log('runs fetched', 'src=', url, 'items=', items.length);
          return { src:url, items, raw:j };
        }
        // keep first successful empty response for debugging, but continue fallback
        if (!bestEmpty) bestEmpty = { src:url, items:[], raw:j };
        log('runs empty from', url, '(fallback continue)');
      }catch(e){
        warn('runs fetch failed', url, String(e?.message || e));
      }
    }
    if (bestEmpty){
      log('runs final empty', 'src=', bestEmpty.src);
      return bestEmpty;
    }
    return { src:'(none)', items:[], raw:{} };
  }

  function fileUrl(rid, path){
    const u = new URL('/api/vsp/run_file_allow', window.location.origin);
    u.searchParams.set('rid', rid);
    u.searchParams.set('path', path);
    return u.toString();
  }

  function buildRow(it){
    const rid = String(it?.rid ?? it?.RID ?? it?.run_id ?? it?.id ?? '');
    const overall = it?.overall ?? it?.status ?? it?.verdict ?? it?.result ?? 'UNKNOWN';
    const st = classifyStatus(overall);
    const label = it?.label ?? it?.note ?? it?.mode ?? it?.type ?? '';
    const ts = it?.ts ?? it?.time ?? it?.created_at ?? it?.started_at ?? '';

    return { rid, overall, st, label, ts, raw: it };
  }

  function render(root, state){
    const { src, items, filter } = state;
    const rows = items.map(buildRow);

    const chips = ['ALL','OK','WARN','FAIL','UNKNOWN'];
    const chipHtml = chips.map(k => {
      const on = (filter.status === k);
      return `<span class="chip ${on?'on':''}" data-chip="${k}">${k}</span>`;
    }).join('');

    const shown = rows.filter(r=>{
      const okStatus = (filter.status==='ALL') || (r.st===filter.status);
      const q = filter.q.trim().toLowerCase();
      const okQ = !q || (
        r.rid.toLowerCase().includes(q) ||
        String(r.overall).toLowerCase().includes(q) ||
        String(r.label).toLowerCase().includes(q) ||
        String(r.ts).toLowerCase().includes(q)
      );
      return okStatus && okQ;
    });

    const head = `
      <div class="vsp_card">
        <div class="vsp_card_hd">
          <div>
            <div class="t">Runs & Reports</div>
            <div class="sub">Commercial list (stable) • source: <code>${esc(src)}</code></div>
          </div>
          <div class="vsp_row">
            <button class="btn" data-act="refresh">Refresh</button>
            <span class="meta">shown: <b>${shown.length}</b> / ${rows.length}</span>
          </div>
        </div>

        <div style="padding:10px 14px;">
          <div class="vsp_row" style="margin-bottom:8px;">${chipHtml}</div>
          <div class="vsp_row">
            <input style="min-width:320px; flex:1;" placeholder="Search RID / status / label / time..." value="${esc(filter.q)}" data-inp="q"/>
            <button class="btn" data-act="clear">Clear</button>
          </div>
        </div>

        ${rows.length===0 ? `<div class="empty">No runs returned yet. If you know runs exist, check API: <code>/api/vsp/runs?limit=250&amp;offset=0</code>.</div>` : `
          <div style="overflow:auto; max-height: 56vh;">
            <table>
              <thead>
                <tr>
                  <th style="min-width:260px;">RID</th>
                  <th style="min-width:90px;">OVERALL</th>
                  <th style="min-width:220px;">LABEL/TS</th>
                  <th style="min-width:360px;">ARTIFACTS</th>
                  <th style="min-width:120px;">ACTIONS</th>
                </tr>
              </thead>
              <tbody>
                ${shown.map(r=>`
                  <tr>
                    <td><code>${esc(r.rid)}</code></td>
                    <td class="st ${esc(r.st)}">${esc(r.st)}</td>
                    <td>${esc(r.label)}<div style="opacity:.75">${esc(r.ts)}</div></td>
                    <td class="links">
                      <a href="${esc(fileUrl(r.rid,'reports/findings_unified.csv'))}">CSV</a>
                      <a href="${esc(fileUrl(r.rid,'reports/findings_unified.html'))}">HTML</a>
                      <a href="${esc(fileUrl(r.rid,'reports/findings_unified.sarif'))}">SARIF</a>
                      <a href="${esc(fileUrl(r.rid,'reports/run_gate_summary.json'))}">SUMMARY</a>
                      <a href="${esc(fileUrl(r.rid,'reports/reports.tgz'))}">reports.tgz</a>
                    </td>
                    <td class="links">
                      <a class="btn" style="display:inline-block;" href="/c/dashboard?rid=${encodeURIComponent(r.rid)}">Open</a>
                    </td>
                  </tr>
                `).join('')}
              </tbody>
            </table>
          </div>
        `}
      </div>
    `;

    root.innerHTML = head;

    // bind
    root.querySelectorAll('[data-chip]').forEach(el=>{
      el.addEventListener('click', ()=>{
        state.filter.status = el.getAttribute('data-chip') || 'ALL';
        render(root, state);
      }, {passive:true});
    });

    const inp = root.querySelector('[data-inp="q"]');
    if (inp){
      inp.addEventListener('input', ()=>{
        state.filter.q = inp.value || '';
        render(root, state);
      }, {passive:true});
    }

    const btnR = root.querySelector('[data-act="refresh"]');
    if (btnR){
      btnR.addEventListener('click', async ()=>{
        btnR.textContent = 'Refreshing...';
        try{
          const r = await fetchRuns();
          state.src = r.src;
          state.items = r.items;
        } finally {
          btnR.textContent = 'Refresh';
          render(root, state);
        }
      });
    }

    const btnC = root.querySelector('[data-act="clear"]');
    if (btnC){
      btnC.addEventListener('click', ()=>{
        state.filter.q = '';
        render(root, state);
      }, {passive:true});
    }
  }

  async function main(){
    injectCss();
    const root = ensureRoot();

    const state = {
      src: '(loading)',
      items: [],
      filter: { status:'ALL', q:'' }
    };

    render(root, state);

    // Keep root alive (legacy scripts may re-render / replace)
    const obs = new MutationObserver(()=>{
      if (!document.getElementById(ROOT_ID)){
        warn('root removed -> reattach');
        injectCss();
        ensureRoot();
        render(document.getElementById(ROOT_ID), state);
      }
    });
    obs.observe(document.documentElement, { childList:true, subtree:true });

    const r = await fetchRuns();
    state.src = r.src;
    state.items = r.items;

    // Light “legacy hide”: ONLY hide obvious legacy empty block text if present
    // (safe: don't hide scan form or top bar)
    try{
      document.querySelectorAll('div,section,article').forEach(el=>{
        if (!el || !el.innerText) return;
        if (el.dataset && el.dataset.vspKeep==='1') return;
        const t = el.innerText;
        if (t.includes('No runs found (yet)') || t.includes('This environment has no run history loaded')){
          el.style.display = 'none';
        }
      });
    }catch(e){}

    render(root, state);
    log('ready');
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', main, { once:true });
  } else {
    main();
  }
})();
"""
p.write_text(js, encoding="utf-8")
print("[OK] rewrote", p)
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" | tee -a "$OUT/log.txt"
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P483g done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
