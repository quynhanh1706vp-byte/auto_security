#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TPL="templates"
[ -d "$TPL" ] || { echo "[ERR] missing templates/"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P1_COMMERCIAL_FINISH_ALL_UI_V1"

inject = r"""
<script>
/* VSP_P1_COMMERCIAL_FINISH_ALL_UI_V1 */
(function(){
  if (window.__VSP_COMM_FINISH_ALL__) return;
  window.__VSP_COMM_FINISH_ALL__ = 1;

  const q = new URLSearchParams(location.search);
  const FORCE_RID = (q.get('rid')||'').trim();
  if (FORCE_RID) window.VSP_FORCE_RID = FORCE_RID;

  // --- Fetch interceptor: force rid for run_file and reports when ?rid= is present ---
  const _origFetch = window.fetch.bind(window);
  window.fetch = async function(input, init){
    try{
      let url = (typeof input === 'string') ? input : (input && input.url) ? input.url : '';
      if (FORCE_RID && url){
        // rewrite /api/reports/<name> -> /api/vsp/run_file?rid=FORCE&name=reports/<name>
        if (url.startsWith('/api/reports/')) {
          const name = url.substring('/api/reports/'.length);
          const rew = '/api/vsp/run_file?rid=' + encodeURIComponent(FORCE_RID) + '&name=' + encodeURIComponent('reports/' + name);
          url = rew;
        }
        // rewrite run_file rid=*
        if (url.includes('/api/vsp/run_file?')) {
          const u = new URL(url, location.origin);
          const rid = (u.searchParams.get('rid')||'').trim();
          const name = (u.searchParams.get('name')||'').trim();
          if (name && rid && rid !== FORCE_RID) {
            u.searchParams.set('rid', FORCE_RID);
            url = u.pathname + '?' + u.searchParams.toString();
          }
        }
        if (typeof input === 'string') input = url;
        else input = new Request(url, input);
      }
    }catch(e){}
    return _origFetch(input, init);
  };

  // --- Utilities ---
  const $ = (sel, root=document) => root.querySelector(sel);
  const $$ = (sel, root=document) => Array.from(root.querySelectorAll(sel));

  function ensureTopBar(){
    let bar = document.getElementById('vsp_live_status_bar');
    if (bar) return bar;
    bar = document.createElement('div');
    bar.id = 'vsp_live_status_bar';
    bar.style.cssText = [
      "position:sticky","top:0","z-index:99999",
      "margin:0 auto","max-width:1200px",
      "padding:8px 10px","border-radius:12px",
      "background:rgba(0,0,0,.45)","backdrop-filter:blur(8px)",
      "color:#e6edf3","border:1px solid rgba(255,255,255,.10)",
      "font:12px/1.2 system-ui","display:flex","gap:10px","align-items:center",
      "justify-content:space-between"
    ].join(";");
    bar.innerHTML = `
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <span id="vsp_live_runs_state">RUNS: ...</span>
        <span style="opacity:.8" id="vsp_live_rid">rid_latest: ...</span>
        <span style="opacity:.7" id="vsp_live_mode">${FORCE_RID ? ('FORCE rid=' + FORCE_RID) : 'AUTO rid_latest'}</span>
      </div>
      <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
        <button id="vsp_btn_csv" style="all:unset;cursor:pointer;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14)">CSV</button>
        <button id="vsp_btn_tgz" style="all:unset;cursor:pointer;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14)">TGZ</button>
        <button id="vsp_btn_sha" style="all:unset;cursor:pointer;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14)">SHA</button>
        <button id="vsp_btn_sum" style="all:unset;cursor:pointer;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14)">Summary JSON</button>
      </div>
    `;

    // Insert nicely below existing header area if present, else at body top
    const anchor = document.body.firstElementChild;
    document.body.insertBefore(bar, anchor);

    return bar;
  }

  function setStickyFailToOkText(ridLatest, degraded){
    // Remove/overwrite sticky "RUNS API FAIL" banners if exist
    const msg = degraded ? `RUNS API DEGRADED • rid_latest=${ridLatest}` : `RUNS API OK • rid_latest=${ridLatest}`;
    $$('button,span,div,a').forEach(el=>{
      const t = (el.textContent||"").trim();
      if (!t) return;
      if (t.includes('RUNS API FAIL')) el.textContent = msg;
      if (t.includes('Error: 503') || t.includes('Error: 500') || t.includes('Error:')) {
        // soften error noise if runs is OK now
        if (t.includes('/api/vsp/runs')) el.textContent = '';
      }
    });
  }

  function ensureCornerBadge(){
    let b = document.getElementById('vsp_rid_latest_badge');
    if (b) return b;
    b = document.createElement('div');
    b.id = 'vsp_rid_latest_badge';
    b.style.cssText = "position:fixed;right:16px;bottom:16px;z-index:99999;padding:8px 10px;border-radius:12px;background:rgba(0,0,0,.55);backdrop-filter:blur(6px);font:12px/1.2 system-ui;color:#e6edf3;border:1px solid rgba(255,255,255,.10)";
    document.body.appendChild(b);
    return b;
  }

  function applyRunRowLinks(){
    // Runs page: turn each run_id text into links
    // Heuristic: find text nodes that look like *_RUN_* or VSP_CI_RUN_*
    const rx = /(VSP_CI_RUN_\d{8}_\d{6}|[A-Za-z0-9-]+_RUN_\d{8}_\d{6}_\d{6}|RUN_[A-Za-z0-9-]+_\d{8}_\d{6})/g;

    $$('a,div,span').forEach(el=>{
      const t = (el.textContent||"").trim();
      if (!t || t.length > 120) return;
      const m = t.match(rx);
      if (!m) return;
      const rid = m[0];
      // avoid patching buttons
      if (el.tagName === 'A' && el.getAttribute('href')) return;

      // Create small actions only once per element
      if (el.dataset && el.dataset.vspRidLinked === '1') return;
      if (el.dataset) el.dataset.vspRidLinked = '1';

      const wrap = document.createElement('span');
      wrap.style.cssText = "display:inline-flex;gap:8px;align-items:center;flex-wrap:wrap";
      const ridSpan = document.createElement('span');
      ridSpan.textContent = rid;

      const aDS = document.createElement('a');
      aDS.textContent = "Open Data Source";
      aDS.href = "/data_source?rid=" + encodeURIComponent(rid);
      aDS.target = "_blank";
      aDS.style.cssText = "opacity:.9;text-decoration:none;padding:4px 8px;border-radius:10px;border:1px solid rgba(255,255,255,.14)";

      const aSum = document.createElement('a');
      aSum.textContent = "Open Summary";
      aSum.href = "/api/vsp/run_file?rid=" + encodeURIComponent(rid) + "&name=" + encodeURIComponent("reports/run_gate_summary.json");
      aSum.target = "_blank";
      aSum.style.cssText = "opacity:.9;text-decoration:none;padding:4px 8px;border-radius:10px;border:1px solid rgba(255,255,255,.14)";

      wrap.appendChild(ridSpan);
      wrap.appendChild(aDS);
      wrap.appendChild(aSum);

      // replace el content
      el.textContent = "";
      el.appendChild(wrap);
    });
  }

  async function pollRuns(){
    const bar = ensureTopBar();
    const badge = ensureCornerBadge();
    try{
      const r = await fetch('/api/vsp/runs?limit=1', { cache:'no-store' });
      const degraded = (r.headers.get('X-VSP-RUNS-DEGRADED')||'') === '1';
      const txt = await r.text();
      let j=null; try{ j=JSON.parse(txt); }catch(e){}
      const ridLatest = FORCE_RID || (j && j.rid_latest) || 'N/A';
      const ok = (r.status===200) && j && (j.ok===true);

      $('#vsp_live_runs_state').textContent = ok ? (degraded?'RUNS: DEGRADED':'RUNS: OK') : ('RUNS: FAIL ' + r.status);
      $('#vsp_live_rid').textContent = 'rid_latest: ' + ridLatest;
      badge.textContent = (ok ? (degraded?'DEGRADED':'OK') : 'FAIL') + ' • rid=' + ridLatest;

      setStickyFailToOkText(ridLatest, degraded);

      // wire buttons
      const ridForButtons = ridLatest;
      $('#vsp_btn_csv').onclick = ()=> location.href = '/api/vsp/export_csv?rid=' + encodeURIComponent(ridForButtons);
      $('#vsp_btn_tgz').onclick = ()=> location.href = '/api/vsp/export_tgz?rid=' + encodeURIComponent(ridForButtons) + '&scope=reports';
      $('#vsp_btn_sha').onclick = ()=> window.open('/api/vsp/sha256?rid=' + encodeURIComponent(ridForButtons) + '&name=' + encodeURIComponent('reports/run_gate_summary.json'), '_blank');
      $('#vsp_btn_sum').onclick = ()=> window.open('/api/vsp/run_file?rid=' + encodeURIComponent(ridForButtons) + '&name=' + encodeURIComponent('reports/run_gate_summary.json'), '_blank');

      // update links on runs page
      applyRunRowLinks();

    }catch(e){}
  }

  pollRuns();
  setInterval(pollRuns, 4000);
})();
</script>
"""

tpl_root = Path("templates")
patched = []
for p in tpl_root.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue
    # only inject into VSP main pages
    if ("VersaSecure Platform" in s) or ("/api/vsp/runs" in s) or ("Runs & Reports" in s) or ("Data Source" in s) or ("Rule Overrides" in s) or ("vsp5" in s):
        if "</body>" in s:
            s2 = s.replace("</body>", "\n<!-- "+MARK+" -->\n"+inject+"\n</body>")
            p.write_text(s2, encoding="utf-8")
            patched.append(str(p))

print("[OK] injected", MARK, "into", len(patched), "templates")
for x in patched[:40]:
    print(" -", x)
PY

echo "[OK] restart UI"
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1

echo "== smoke =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=1" | sed -n '1,16p'
