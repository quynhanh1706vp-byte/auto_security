#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need sed; need date

TPL="templates/vsp_dashboard_2025.html"
JS="static/js/vsp_summary_only_banner_p0_v1.js"
MARK="VSP_SUMMARY_ONLY_BANNER_P0_V1"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_${MARK}_${TS}"
echo "[BACKUP] $TPL.bak_${MARK}_${TS}"

mkdir -p static/js

# (1) write JS (idempotent overwrite OK)
cat > "$JS" <<'JSX'
(function(){
  'use strict';
  if (window.__VSP_SUMMARY_ONLY_BANNER_P0_V1) return;
  window.__VSP_SUMMARY_ONLY_BANNER_P0_V1 = true;

  function el(tag, cls, txt){
    var e=document.createElement(tag);
    if(cls) e.className=cls;
    if(txt!=null) e.textContent=txt;
    return e;
  }

  function pick(obj, path, dflt){
    try{
      return path.split('.').reduce(function(a,k){ return (a && (k in a)) ? a[k] : undefined; }, obj) ?? dflt;
    }catch(_){ return dflt; }
  }

  function looksSummaryOnly(payload){
    var notes = pick(payload,'notes',[]);
    var s = Array.isArray(notes) ? notes.join(' | ') : String(notes||'');
    if (/placeholder generated/i.test(s)) return true;
    if (Array.isArray(payload.findings) && payload.findings.length===0 && Array.isArray(payload.items) && payload.items.length>0) return true;
    return false;
  }

  function kicsCountsFromItems(items){
    var out = {HIGH:0, MEDIUM:0, LOW:0, INFO:0, CRITICAL:0, TRACE:0};
    if (!Array.isArray(items)) return out;
    for (var i=0;i<items.length;i++){
      var it=items[i]||{};
      if ((it.tool||'')!=='KICS') continue;
      var sev = (it.severity||'').toUpperCase();
      var c = Number(it.count||0);
      if (!Number.isFinite(c)) c=0;
      if (sev in out) out[sev]+=c;
    }
    return out;
  }

  function injectBanner(payload){
    var summaryOnly = looksSummaryOnly(payload);
    if (!summaryOnly) return;

    var host = document.querySelector('#vspMain') || document.querySelector('main') || document.body;
    if (!host) return;

    if (document.getElementById('vspSummaryOnlyBanner')) return;

    var counts = kicsCountsFromItems(payload.items);
    var wrap = el('div', 'vsp-summary-only-wrap');
    wrap.id='vspSummaryOnlyBanner';

    var left = el('div','vsp-summary-only-left');
    var title = el('div','vsp-summary-only-title','SUMMARY-ONLY MODE');
    var sub = el('div','vsp-summary-only-sub','Raw findings chưa ingest; dashboard đang hiển thị theo summary/stub để không “đơ” pipeline.');

    left.appendChild(title);
    left.appendChild(sub);

    var right = el('div','vsp-summary-only-right');

    function pill(label, val){
      var p = el('div','vsp-pill');
      p.appendChild(el('span','vsp-pill-k',label));
      p.appendChild(el('span','vsp-pill-v',String(val)));
      return p;
    }

    // show KICS prominently if any
    right.appendChild(el('div','vsp-summary-only-kics','KICS (summary)'));
    var row = el('div','vsp-pill-row');
    row.appendChild(pill('HIGH', counts.HIGH));
    row.appendChild(pill('MEDIUM', counts.MEDIUM));
    row.appendChild(pill('LOW', counts.LOW));
    row.appendChild(pill('INFO', counts.INFO));
    right.appendChild(row);

    wrap.appendChild(left);
    wrap.appendChild(right);

    // inject at top
    host.insertBefore(wrap, host.firstChild);

    // add soft dim to drilldown links if present
    var dl = document.querySelectorAll('[data-drilldown], .drilldown, a[href*="findings"]');
    for (var j=0;j<dl.length;j++){
      dl[j].classList.add('vsp-drilldown-disabled');
      dl[j].setAttribute('title','SUMMARY-ONLY: raw findings chưa có nên drilldown bị hạn chế.');
    }
  }

  // minimal CSS injection (no dependency)
  function injectCSS(){
    if (document.getElementById('vspSummaryOnlyCSS')) return;
    var css = `
#vspSummaryOnlyBanner{
  margin: 10px 0 14px 0;
  padding: 12px 14px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.14);
  background: linear-gradient(90deg, rgba(255,196,0,0.10), rgba(255,77,0,0.08));
  display:flex; gap:12px; align-items:center; justify-content:space-between;
}
.vsp-summary-only-title{ font-weight:800; letter-spacing:0.6px; }
.vsp-summary-only-sub{ opacity:0.85; font-size: 12.5px; margin-top:2px; }
.vsp-summary-only-right{ display:flex; flex-direction:column; align-items:flex-end; gap:6px; }
.vsp-summary-only-kics{ font-weight:700; opacity:0.9; font-size:12px; }
.vsp-pill-row{ display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; }
.vsp-pill{
  border:1px solid rgba(255,255,255,0.18);
  background: rgba(0,0,0,0.25);
  padding: 6px 10px;
  border-radius: 999px;
  display:flex; gap:8px; align-items:center;
  font-size:12px;
}
.vsp-pill-k{ opacity:0.8; font-weight:700; }
.vsp-pill-v{ font-weight:800; }
.vsp-drilldown-disabled{ opacity:0.55; pointer-events:none; }
`;
    var st=document.createElement('style');
    st.id='vspSummaryOnlyCSS';
    st.textContent=css;
    document.head.appendChild(st);
  }

  async function boot(){
    injectCSS();
    // Try to read same-origin findings_unified.json (served by UI gateway normally)
    var url = '/findings_unified.json?ts=' + Date.now();
    try{
      var r = await fetch(url, {cache:'no-store'});
      if(!r.ok) return;
      var payload = await r.json();
      injectBanner(payload);
    }catch(_){}
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
JSX

# (2) Ensure template includes script tag once
if ! grep -q "$MARK" "$TPL"; then
  # insert before </body>
  sed -i "s#</body>#  <!-- ${MARK} -->\n  <script src=\"/static/js/vsp_summary_only_banner_p0_v1.js\"></script>\n</body>#i" "$TPL"
  echo "[OK] injected script tag into $TPL"
else
  echo "[OK] template already has $MARK"
fi

# (3) quick sanity
python3 - <<'PY'
import json, pathlib
p=pathlib.Path("static/js/vsp_summary_only_banner_p0_v1.js")
assert p.exists() and p.stat().st_size>200
print("[OK] js bytes=", p.stat().st_size)
PY

echo "[NEXT] restart UI (gunicorn/systemd) then hard refresh Ctrl+Shift+R"
