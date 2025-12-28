#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3
command -v node >/dev/null 2>&1 && HAVE_NODE=1 || HAVE_NODE=0

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_console_donut_${TS}"
echo "[BACKUP] ${JS}.bak_console_donut_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_CONSOLE_CLEAN_DONUT_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

patch = r"""
/* === VSP_P1_CONSOLE_CLEAN_DONUT_V1 === */
(function(){
  'use strict';
  const MARK="VSP_P1_CONSOLE_CLEAN_DONUT_V1";
  if (window.__vsp_p1_console_clean_donut_v1) return;
  window.__vsp_p1_console_clean_donut_v1 = true;

  // 1) drop ONLY known noisy logs (keep real errors)
  const DROP_LOG = [
    /\[VSP\]\[DASH\]\[V6[^\]]*\]\s*(check ids|ids=)/i,
    /\bcanvas-rendered\b/i,
    /\bChartJs\s*=\s*false\b/i
  ];
  const DROP_WARN = [
    /\bgave up\b.*\(chart\/container missing\)/i,
    /\bchart\/container missing\b/i
  ];

  function shouldDrop(args, arr){
    try{
      if (!args || !args.length) return false;
      const s0 = (typeof args[0] === "string") ? args[0] : "";
      return arr.some(rx => rx.test(s0));
    }catch(_){ return false; }
  }

  const olog = console.log.bind(console);
  const owarn = console.warn.bind(console);
  console.log = function(...a){ if (shouldDrop(a, DROP_LOG)) return; return olog(...a); };
  console.warn = function(...a){ if (shouldDrop(a, DROP_WARN)) return; return owarn(...a); };

  // 2) Fix donut label: show "sample / total"
  function fixDonutLabel(){
    try{
      // total findings from KPI
      let total='';
      const k = Array.from(document.querySelectorAll('*')).find(el => (el.textContent||'').trim()==='TOTAL FINDINGS');
      if (k){
        const box = k.closest('div') || k.parentElement;
        const m = (box ? (box.textContent||'') : '').match(/TOTAL FINDINGS\s*([0-9][0-9,]*)/i);
        if (m) total = m[1].replace(/,/g,'');
      }
      if (!total) return;

      // find the "SEVERITY DISTRIBUTION" card
      const h = Array.from(document.querySelectorAll('*')).find(el => (el.textContent||'').trim()==='SEVERITY DISTRIBUTION');
      if (!h) return;
      const card = h.closest('div') || h.parentElement;
      if (!card) return;

      // inside that card, find a small text node containing "<num> total"
      const nodes = Array.from(card.querySelectorAll('*'))
        .filter(el => el.children.length===0)
        .slice(0,200);

      let target=null, sample='';
      for (const el of nodes){
        const tx=(el.textContent||'').trim();
        const m=tx.match(/^(\d[\d,]*)\s*total$/i);
        if (m){ target=el; sample=m[1].replace(/,/g,''); break; }
      }
      if (!target || !sample) return;

      const want = `${sample} sample / ${total} total`;
      if ((target.textContent||'').trim() !== want) target.textContent = want;
    }catch(_){}
  }

  // run a few times (DOM loads late)
  setTimeout(fixDonutLabel, 300);
  setTimeout(fixDonutLabel, 900);
  setTimeout(fixDonutLabel, 1800);
})();
"""
p.write_text(s.rstrip()+"\n\n"+patch+"\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

if [ "$HAVE_NODE" = "1" ]; then
  node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
else
  echo "[WARN] node not found; skipped node --check"
fi

# restart UI (your proven way)
rm -f /tmp/vsp_ui_8910.lock || true
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

echo "DONE. Ctrl+F5 /vsp5 then check: console cleaner + donut shows 'sample/total'."
