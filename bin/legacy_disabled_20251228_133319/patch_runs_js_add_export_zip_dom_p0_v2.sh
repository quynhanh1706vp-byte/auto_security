#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need grep; need awk; need wc; need date; need python3; need node

echo "== find candidate JS containing /api/vsp/runs or /api/vsp/run_file =="
CANDS="$(grep -RIl -E '/api/vsp/(runs|run_file)' static/js 2>/dev/null || true)"
[ -n "${CANDS:-}" ] || { echo "[ERR] no candidate JS in static/js"; ls -la static/js | head; exit 2; }

BEST="$(echo "$CANDS" | while read -r f; do
  c1=$(grep -c '/api/vsp/run_file' "$f" 2>/dev/null || echo 0)
  c2=$(grep -c '/api/vsp/runs' "$f" 2>/dev/null || echo 0)
  sz=$(wc -c <"$f" 2>/dev/null || echo 0)
  echo "$c1 $c2 $sz $f"
done | sort -nr | head -n1 | awk '{print $4}')"

echo "[OK] picked JS: $BEST"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BEST" "${BEST}.bak_exportzip_dom_${TS}"
echo "[BACKUP] ${BEST}.bak_exportzip_dom_${TS}"

python3 - <<PY
from pathlib import Path
js_path = Path("$BEST")
s = js_path.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_RUNS_EXPORT_ZIP_DOM_P0_V2"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

patch = r'''
;(()=>{ // VSP_RUNS_EXPORT_ZIP_DOM_P0_V2
  try{
    if (window.__VSP_RUNS_EXPORT_ZIP_DOM_P0_V2) return;
    window.__VSP_RUNS_EXPORT_ZIP_DOM_P0_V2 = 1;

    function ridFromHref(href){
      try{
        const u = new URL(href, window.location.origin);
        if (!u.pathname.includes('/api/vsp/run_file')) return null;
        return u.searchParams.get('run_id');
      }catch(e){ return null; }
    }

    function addBtnNear(anchor, rid){
      try{
        const row = anchor.closest('tr') || anchor.parentElement;
        if (!row) return;
        if (row.querySelector('a[data-vsp-export-zip="1"]')) return;

        const a = document.createElement('a');
        a.textContent = 'Export ZIP';
        a.href = '/api/vsp/export_zip?run_id=' + encodeURIComponent(rid);
        a.setAttribute('data-vsp-export-zip','1');
        a.style.marginLeft = '8px';
        a.style.textDecoration = 'none';
        a.style.display = 'inline-block';
        a.style.padding = '7px 10px';
        a.style.borderRadius = '10px';
        a.style.fontWeight = '800';
        a.style.border = '1px solid rgba(90,140,255,.35)';
        a.style.background = 'rgba(90,140,255,.16)';
        a.style.color = 'inherit';

        anchor.insertAdjacentElement('afterend', a);
      }catch(_e){}
    }

    function patchOnce(){
      const links = Array.from(document.querySelectorAll('a[href*="/api/vsp/run_file"]'));
      if (!links.length) return;
      const seen = new Set();
      for (const a of links){
        const rid = ridFromHref(a.getAttribute('href')||'');
        if (!rid) continue;
        const key = rid + '::' + (a.closest('tr') ? a.closest('tr').rowIndex : 'x');
        if (seen.has(key)) continue;
        seen.add(key);
        addBtnNear(a, rid);
      }
    }

    let n=0;
    const t=setInterval(()=>{ n++; patchOnce(); if(n>=30) clearInterval(t); }, 300);
    window.addEventListener('load', ()=>{ try{patchOnce();}catch(_e){} }, {once:true});
  }catch(_e){}
})();
'''
js_path.write_text(s.rstrip()+"\n\n"+patch+"\n", encoding="utf-8")
print("[OK] appended DOM patcher:", js_path)
PY

node --check "$BEST" >/dev/null 2>&1 || { echo "[ERR] node --check failed for $BEST"; node --check "$BEST"; exit 3; }
echo "[OK] node --check OK"

echo "[NEXT] restart 8910 and hard refresh /runs"
