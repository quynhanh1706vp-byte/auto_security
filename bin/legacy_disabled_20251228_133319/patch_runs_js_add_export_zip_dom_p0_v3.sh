#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need grep; need awk; need wc; need date; need python3; need node

echo "== find candidate LIVE JS (exclude .bak*) =="
CANDS="$(grep -RIl -E '/api/vsp/(runs|run_file)' static/js 2>/dev/null | grep -v '\.bak' || true)"
[ -n "${CANDS:-}" ] || { echo "[ERR] no LIVE JS candidate (exclude .bak)"; exit 2; }

BEST="$(echo "$CANDS" | while read -r f; do
  c1=$(grep -c '/api/vsp/run_file' "$f" 2>/dev/null || echo 0)
  c2=$(grep -c '/api/vsp/runs' "$f" 2>/dev/null || echo 0)
  sz=$(wc -c <"$f" 2>/dev/null || echo 0)
  echo "$c1 $c2 $sz $f"
done | sort -nr | head -n1 | awk '{print $4}')"

echo "[OK] picked LIVE JS: $BEST"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BEST" "${BEST}.bak_exportzip_dom_${TS}"
echo "[BACKUP] ${BEST}.bak_exportzip_dom_${TS}"

python3 - <<PY
from pathlib import Path
js_path = Path("$BEST")
s = js_path.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_RUNS_EXPORT_ZIP_DOM_P0_V3"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

patch = r'''
;(()=>{ // VSP_RUNS_EXPORT_ZIP_DOM_P0_V3
  try{
    if (window.__VSP_RUNS_EXPORT_ZIP_DOM_P0_V3) return;
    window.__VSP_RUNS_EXPORT_ZIP_DOM_P0_V3 = 1;

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
    const t=setInterval(()=>{ n++; patchOnce(); if(n>=40) clearInterval(t); }, 250);
    window.addEventListener('load', ()=>{ try{patchOnce();}catch(_e){} }, {once:true});
  }catch(_e){}
})();
'''
js_path.write_text(s.rstrip()+"\n\n"+patch+"\n", encoding="utf-8")
print("[OK] patched LIVE JS:", js_path)
PY

# syntax check without caring about extension mode
node --check --input-type=commonjs "$BEST" >/dev/null 2>&1 || { echo "[ERR] node --check failed for $BEST"; node --check --input-type=commonjs "$BEST"; exit 3; }
echo "[OK] node --check OK"

echo "[NEXT] restart 8910 then hard refresh /runs"
