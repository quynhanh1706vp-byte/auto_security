#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3
command -v node >/dev/null 2>&1 && HAVE_NODE=1 || HAVE_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"

# --- 1) Inject EARLY console filter in template (runs before bundle) ---
TPL="templates/vsp_5tabs_enterprise_v2.html"
if [ -f "$TPL" ]; then
  cp -f "$TPL" "${TPL}.bak_console_early_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re

p = Path("templates/vsp_5tabs_enterprise_v2.html")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_EARLY_CONSOLE_FILTER_V2"
if MARK in s:
    print("[OK] template already has", MARK)
    raise SystemExit(0)

inject = r"""
<!-- VSP_P1_EARLY_CONSOLE_FILTER_V2 -->
<script id="VSP_P1_EARLY_CONSOLE_FILTER_V2">
(()=> {
  if (window.__vsp_p1_early_console_filter_v2) return;
  window.__vsp_p1_early_console_filter_v2 = true;

  // Drop ONLY known-noisy messages (keep real errors)
  const DROP_LOG = [
    /\[VSP\]\[P1\]\s*(fetch wrapper enabled|runs-fail banner auto-clear enabled|fetch limit patched|nav dedupe applied|rule overrides metrics\/table synced)/i,
    /\[VSP\]\[DASH\].*(check ids|ids=)/i,
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
  const oinfo = console.info.bind(console);
  const owarn = console.warn.bind(console);

  console.log  = (...a)=> shouldDrop(a, DROP_LOG)  ? void 0 : olog(...a);
  console.info = (...a)=> shouldDrop(a, DROP_LOG)  ? void 0 : oinfo(...a);
  console.warn = (...a)=> shouldDrop(a, DROP_WARN) ? void 0 : owarn(...a);
})();
</script>
"""

m = re.search(r"<head[^>]*>", s, flags=re.I)
if not m:
    print("[ERR] <head> tag not found in template")
    raise SystemExit(2)

pos = m.end()
s2 = s[:pos] + "\n" + inject + "\n" + s[pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected early console filter:", MARK)
PY
else
  echo "[WARN] missing template $TPL (skip early console filter)"
fi

# --- 2) Add donut overlay (sample/total) into bundle (guaranteed visible) ---
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "${JS}.bak_donut_overlay_${TS}"
echo "[BACKUP] ${JS}.bak_donut_overlay_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_DONUT_OVERLAY_SAMPLE_TOTAL_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

patch = r"""
/* === VSP_P1_DONUT_OVERLAY_SAMPLE_TOTAL_V2 === */
(()=> {
  if (window.__vsp_p1_donut_overlay_v2) return;
  window.__vsp_p1_donut_overlay_v2 = true;

  function findNumberNearLabel(label){
    try{
      const els = Array.from(document.querySelectorAll('*'));
      const hit = els.find(el => (el.textContent||'').trim() === label);
      if (!hit) return '';
      const box = hit.closest('div') || hit.parentElement;
      if (!box) return '';
      const t = (box.textContent||'').replace(/\s+/g,' ');
      const esc = label.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
      const rx = new RegExp(esc + '\\s*([0-9][0-9,]*)', 'i');
      const m = t.match(rx);
      return m ? m[1].replace(/,/g,'') : '';
    }catch(_){ return ''; }
  }

  function findSampleInSeverityCard(card){
    try{
      const leaf = Array.from(card.querySelectorAll('*')).filter(el => el.children.length===0);
      for (const el of leaf){
        const tx=(el.textContent||'').trim();
        const m = tx.match(/^(\d[\d,]*)\s*total$/i);
        if (m) return {el, n:m[1].replace(/,/g,'')};
      }
    }catch(_){}
    return {el:null, n:''};
  }

  function apply(){
    try{
      const total = findNumberNearLabel('TOTAL FINDINGS');
      if (!total) return;

      const h = Array.from(document.querySelectorAll('*')).find(el => (el.textContent||'').trim()==='SEVERITY DISTRIBUTION');
      if (!h) return;
      const card = h.closest('div') || h.parentElement;
      if (!card) return;

      const {el:oldLabel, n:sample} = findSampleInSeverityCard(card);
      if (!sample) return;

      const id = 'vsp_donut_overlay_sample_total_v2';
      let ov = document.getElementById(id);
      if (!ov){
        ov = document.createElement('div');
        ov.id = id;
        ov.style.position = 'absolute';
        ov.style.inset = '0';
        ov.style.display = 'flex';
        ov.style.alignItems = 'center';
        ov.style.justifyContent = 'center';
        ov.style.pointerEvents = 'none';
        ov.style.fontWeight = '700';
        ov.style.fontSize = '14px';
        ov.style.lineHeight = '1.2';
        ov.style.opacity = '0.92';

        const canvas = card.querySelector('canvas');
        const host = (canvas && canvas.parentElement) ? canvas.parentElement : card;
        const hs = getComputedStyle(host);
        if (hs.position === 'static') host.style.position = 'relative';
        host.appendChild(ov);
      }

      ov.textContent = `${sample} sample / ${total} total`;

      if (oldLabel && oldLabel !== ov){
        oldLabel.style.opacity = '0';
      }
    }catch(_){}
  }

  setTimeout(apply, 300);
  setTimeout(apply, 900);
  setTimeout(apply, 1800);
  setTimeout(apply, 3200);
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

# --- 3) Restart UI (your proven way) ---
rm -f /tmp/vsp_ui_8910.lock || true
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

echo "DONE. Ctrl+F5 /vsp5. Expect: console cleaner + warning gone + donut shows 'sample / total'."
