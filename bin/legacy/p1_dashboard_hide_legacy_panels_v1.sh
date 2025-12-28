#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_hidelegacy_${TS}"
echo "[BACKUP] ${TPL}.bak_hidelegacy_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DASH_HIDE_LEGACY_PANELS_V1"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

inject = textwrap.dedent(r"""
<!-- VSP_P1_DASH_HIDE_LEGACY_PANELS_V1 -->
<style>
/* Hide obvious legacy blocks safely (do not affect data contract) */
.vsp-legacy-hide { display:none !important; }
</style>

<script>
(()=>{ try{
  const HARD_REMOVE = (el)=>{ try{ el.remove(); }catch(_){ el.classList.add("vsp-legacy-hide"); } };

  const hasText = (el, needle)=>{
    try{ return (el && el.innerText && el.innerText.indexOf(needle) >= 0); }catch(_){ return false; }
  };

  const findLegacyRoots = ()=>{
    const roots = new Set();
    const cands = document.querySelectorAll("section,div,article,main");
    for (const el of cands){
      // Legacy fingerprint strings observed in your screenshots
      if (hasText(el, "served_by:") || hasText(el, "Degraded mode:") || hasText(el, "RANS_ROOT") ||
          hasText(el, "Dashboard Live") && hasText(el, "latest: RUN_") ||
          hasText(el, "Commercial Panels") || hasText(el, "Gate Story") && hasText(el, "Tool truth") ) {
        // remove nearest reasonable container (card/panel)
        let r = el;
        for (let k=0;k<6;k++){
          if (!r || !r.parentElement) break;
          const cls = (r.className||"").toString();
          if (cls.includes("card") || cls.includes("panel") || cls.includes("container")) break;
          r = r.parentElement;
        }
        roots.add(r || el);
      }

      // If it contains a button labeled "Legacy", it's definitely old UI
      try{
        const btns = el.querySelectorAll("button,a");
        for (const b of btns){
          const t = (b.innerText||"").trim();
          if (t === "Legacy" || t === "Runs" && hasText(el,"served_by:")){
            roots.add(el);
            break;
          }
        }
      }catch(_){}
    }
    return Array.from(roots);
  };

  const cleanOnce = ()=>{
    const roots = findLegacyRoots();
    for (const r of roots) HARD_REMOVE(r);
  };

  // Run early + after a short delay (in case bundle renders later)
  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", cleanOnce, {once:true});
  } else {
    cleanOnce();
  }
  setTimeout(cleanOnce, 400);
  setTimeout(cleanOnce, 1200);

  console.log("[VSP][DASH] legacy panels removed (template-level)");
}catch(_){}})();
</script>
<!-- /VSP_P1_DASH_HIDE_LEGACY_PANELS_V1 -->
""").strip()

# Inject right after <head> open
s2 = re.sub(r'(<head[^>]*>)', r'\1\n' + inject + "\n", s, count=1, flags=re.I)
tpl.write_text(s2, encoding="utf-8")
print("[OK] patched template:", tpl)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
