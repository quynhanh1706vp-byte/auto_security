#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TEMPLATE="templates/vsp_dashboard_2025.html"
JS="static/js/vsp_dashboard_cio_kpi_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
export VSP_P963G_TS="$TS"

OUT="out_ci/p963g_${TS}"
mkdir -p "$OUT"

[ -f "$TEMPLATE" ] || { echo "[ERR] missing $TEMPLATE"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$TEMPLATE" "$OUT/$(basename "$TEMPLATE").bak_${TS}"
cp -f "$JS" "$OUT/$(basename "$JS").bak_${TS}"
echo "[OK] backups => $OUT"

echo "== [1] bump template script ?v= to TS =="
python3 - <<'PY'
from pathlib import Path
import re, os

TS=os.environ.get("VSP_P963G_TS","0")
p=Path("templates/vsp_dashboard_2025.html")
s=p.read_text(encoding="utf-8", errors="replace")

name="vsp_dashboard_cio_kpi_v1.js"
# bump existing ?v=
pat=re.compile(rf'(<script[^>]+{re.escape(name)}\?v=)([^"]+)(\"[^>]*></script>)', re.I)
if pat.search(s):
    s=pat.sub(rf"\1{TS}\3", s, count=1)
    p.write_text(s, encoding="utf-8")
    print("[OK] bumped ?v= in existing script tag")
    raise SystemExit(0)

# else inject before </html>
tag=f'<script src="/static/js/{name}?v={TS}"></script>\n'
m=re.search(r"</html\s*>", s, flags=re.I)
if m:
    s=s[:m.start()]+tag+s[m.start():]
else:
    s=s.rstrip()+"\n"+tag
p.write_text(s, encoding="utf-8")
print("[OK] injected KPI script tag (fallback)")
PY

echo "== [2] patch KPI JS: prefer rid from URL + call kpi_counts_v2 + force visible block =="
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_cio_kpi_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="/* VSP_P963G_WIRE_V2 */"
if marker in s:
    print("[OK] P963G already applied")
    raise SystemExit(0)

addon = r'''
''' + marker + r'''
(function(){
  try{
    console.log('[VSP CIO KPI] P963G loaded', new Date().toISOString());

    function ridFromURL(){
      try{
        var sp = new URLSearchParams(window.location.search || '');
        var rid = sp.get('rid') || sp.get('RID') || '';
        return String(rid||'').trim();
      }catch(e){ return ''; }
    }

    function setText(sel, v){
      var el = document.querySelector(sel);
      if(!el) return false;
      el.textContent = String(v);
      return true;
    }

    function updateExistingKPIs(counts){
      var total = 0;
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){ total += (counts[k]||0); });

      // common ids
      setText('#kpi_total', total);
      setText('#kpi_critical', counts.CRITICAL||0);
      setText('#kpi_high', counts.HIGH||0);
      setText('#kpi_medium', counts.MEDIUM||0);
      setText('#kpi_low', counts.LOW||0);
      setText('#kpi_info', counts.INFO||0);
      setText('#kpi_trace', counts.TRACE||0);

      // data attrs
      ['TOTAL','CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var v = (k==='TOTAL') ? total : (counts[k]||0);
        var el = document.querySelector('[data-kpi="'+k+'"],[data-kpi-key="'+k+'"],[data-sev="'+k+'"]');
        if (el) el.textContent = String(v);
      });
    }

    function forceBlock(counts, meta){
      var root = document.getElementById('vsp_cio_kpi_root');
      if(!root) return;

      root.innerHTML = '';
      var h = document.createElement('div');
      h.className='vsp-cio-kpi-meta';
      h.innerHTML = '<b>CIO KPI (v2)</b> rid=<code>'+String(meta && meta.rid || '')+'</code> n='+String(meta && meta.n || '')+'';
      root.appendChild(h);

      var g = document.createElement('div');
      g.className='vsp-cio-kpi-grid';
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var c = document.createElement('div');
        c.className='vsp-cio-kpi-card';
        c.innerHTML =
          '<div class="vsp-cio-kpi-top"><div class="vsp-cio-kpi-title">'+k+'</div><div class="vsp-cio-kpi-num">'+(counts[k]||0)+'</div></div>' +
          '<div class="vsp-cio-kpi-sub">click to drill-down</div>';
        c.addEventListener('click', function(){
          window.location.href = '/data_source?severity='+encodeURIComponent(k);
        });
        g.appendChild(c);
      });
      root.appendChild(g);
    }

    function fetchV2(rid){
      return fetch('/api/vsp/kpi_counts_v2?rid='+encodeURIComponent(rid), {credentials:'same-origin'})
        .then(function(r){ return r.json(); });
    }

    // Shadow boot: rid-from-URL first, else keep existing logic
    if (typeof boot === 'function') {
      var oldBoot = boot;
      boot = function(){
        var rid = ridFromURL();
        if(!rid){ oldBoot(); return; }
        fetchV2(rid).then(function(j){
          var counts = (j && j.counts) ? j.counts : {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
          updateExistingKPIs(counts);
          forceBlock(counts, {rid: rid, n: (j && j.n)||0});
        }).catch(function(e){
          console.warn('[VSP CIO KPI] kpi_counts_v2 failed', e);
          oldBoot();
        });
      };
    }
  }catch(e){
    console.warn('[VSP CIO KPI] P963G init error', e);
  }
})();
'''
p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended P963G wiring block")
PY

echo "== [3] restart+wait =="
sudo -v || true
sudo systemctl restart "$SVC" || true
VSP_UI_BASE="$BASE" MAX_WAIT=45 bash bin/ops/ops_restart_wait_ui_v1.sh

echo "[PASS] P963Gv2 applied. Open /vsp5?rid=... then Ctrl+Shift+R"
