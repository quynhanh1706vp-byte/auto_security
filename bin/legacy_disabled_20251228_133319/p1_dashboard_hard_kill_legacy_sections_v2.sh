#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_killlegacy2_${TS}"
echo "[BACKUP] ${TPL}.bak_killlegacy2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DASH_HARD_KILL_LEGACY_SECTIONS_V2"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

inject = textwrap.dedent(r"""
<!-- VSP_P1_DASH_HARD_KILL_LEGACY_SECTIONS_V2 -->
<style>
/* Safety class (used as fallback if remove() fails) */
.vsp-legacy-killed { display:none !important; }
</style>
<script>
(()=>{ try{
  const HARD_REMOVE = (el)=>{
    try{ el.remove(); return true; }catch(_){}
    try{ el.classList.add("vsp-legacy-killed"); return true; }catch(_){}
    return false;
  };

  const textOf = (el)=>{
    try{ return (el && (el.innerText||"") || "").trim(); }catch(_){ return ""; }
  };

  // Legacy fingerprints observed in your current UI
  const LEGACY_NEEDLES = [
    "Gate Story",
    "Commercial Panels",
    "Quick Actions",
    "Use RID",
    "Sync latest",
    "Auto latest",
    "RID event:",
    "Run Trend",
    "Hard refresh",
  ];

  const hasLegacyNeedle = (t)=>{
    if (!t) return false;
    for (const n of LEGACY_NEEDLES){
      if (t.includes(n)) return true;
    }
    return false;
  };

  // Find a "panel root" to remove: climb up to a reasonable container
  const findPanelRoot = (el)=>{
    let r = el;
    for (let i=0;i<10;i++){
      if (!r || !r.parentElement) break;
      const cls = (r.className||"").toString();
      // Common container hints
      if (cls.includes("card") || cls.includes("panel") || cls.includes("container") || cls.includes("section")) break;
      r = r.parentElement;
    }
    return r || el;
  };

  const killLegacyOnce = ()=>{
    const cands = document.querySelectorAll("section,div,article,main");
    let killed = 0;
    for (const el of cands){
      const t = textOf(el);
      if (!t) continue;

      // If it contains a "Legacy" button/tab -> definitely legacy block
      let hasLegacyBtn = false;
      try{
        const btns = el.querySelectorAll("button,a");
        for (const b of btns){
          const bt = (b.innerText||"").trim();
          if (bt === "Legacy" || bt === "Runs" && t.includes("Use RID")) { hasLegacyBtn = true; break; }
        }
      }catch(_){}

      if (hasLegacyBtn || hasLegacyNeedle(t)){
        // Don’t accidentally remove the whole page: require at least 2 needles or legacy button
        const hits = LEGACY_NEEDLES.filter(n => t.includes(n)).length;
        if (!hasLegacyBtn && hits < 2) continue;

        const root = findPanelRoot(el);
        if (root && !root.__vsp_killed){
          root.__vsp_killed = true;
          if (HARD_REMOVE(root)) killed++;
        }
      }
    }
    if (killed) console.log("[VSP][DASH] legacy sections killed:", killed);
  };

  // Run now + after render + keep watching
  killLegacyOnce();
  setTimeout(killLegacyOnce, 300);
  setTimeout(killLegacyOnce, 900);
  setTimeout(killLegacyOnce, 1800);

  const mo = new MutationObserver(()=>{ killLegacyOnce(); });
  mo.observe(document.documentElement, {subtree:true, childList:true});
}catch(_){}})();
</script>
<!-- /VSP_P1_DASH_HARD_KILL_LEGACY_SECTIONS_V2 -->
""").strip()

# Inject after <head> open
s2 = re.sub(r'(<head[^>]*>)', r'\1\n' + inject + "\n", s, count=1, flags=re.I)
tpl.write_text(s2, encoding="utf-8")
print("[OK] patched template:", tpl)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
