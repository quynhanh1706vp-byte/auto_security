#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_hide_dup_nav_${TS}"
echo "[BACKUP] ${JS}.bak_hide_dup_nav_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_HIDE_DUPLICATE_NAV_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_HIDE_DUPLICATE_NAV_V1
   /vsp5 has top nav (safe-mode HTML). Hide the injected bottom nav row to look commercial.
*/
(()=> {
  try{
    if (window.__vsp_p1_hide_dup_nav_v1) return;
    window.__vsp_p1_hide_dup_nav_v1 = true;
    if (!(location && location.pathname && location.pathname.indexOf("/vsp5")===0)) return;

    const st = document.createElement("style");
    st.id = "vsp5_hide_dup_nav_style_v1";
    st.textContent = `
      /* Hide bottom nav pills row (we keep the top .vsp5nav) */
      #vsp_dash_p1_wrap a[href="/vsp5"],
      #vsp_dash_p1_wrap a[href="/runs"],
      #vsp_dash_p1_wrap a[href="/data_source"],
      #vsp_dash_p1_wrap a[href="/settings"],
      #vsp_dash_p1_wrap a[href="/rule_overrides"]{
        /* only hide when in a nav-like cluster: parent is flex row near top */
      }
      /* Safe heuristic: hide the SECOND nav row inserted under "VSP • Dashboard" */
      #vsp_dash_p1_wrap > div:nth-child(1) + div a.vsp_btn[href="/runs"],
      #vsp_dash_p1_wrap > div:nth-child(1) + div a.vsp_btn[href="/data_source"],
      #vsp_dash_p1_wrap > div:nth-child(1) + div a.vsp_btn[href="/settings"],
      #vsp_dash_p1_wrap > div:nth-child(1) + div a.vsp_btn[href="/rule_overrides"]{
        display:none !important;
      }
    `;
    (document.head||document.documentElement).appendChild(st);
    console.log("[VSP][ui] hid duplicate nav row");
  }catch(e){
    console.warn("[VSP][ui] hide dup nav failed", e);
  }
})();
"""
p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended hide-dup-nav block")
PY

node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] Hard reload /vsp5 (Ctrl+Shift+R)."
