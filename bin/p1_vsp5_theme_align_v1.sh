#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_theme_align_${TS}"
echo "[BACKUP] ${JS}.bak_theme_align_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_VSP5_THEME_ALIGN_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_VSP5_THEME_ALIGN_V1
   Goal: align /vsp5 SAFE MODE typography/colors with other 5 tabs.
   - inject shared CSS: /static/css/vsp_dark_commercial_p1_2.css (if present)
   - override minimal /vsp5 inline styles to match dark commercial look
*/
(()=> {
  try{
    if (window.__vsp_p1_vsp5_theme_align_v1) return;
    window.__vsp_p1_vsp5_theme_align_v1 = true;

    const isDash = ()=> (location && location.pathname && location.pathname.indexOf("/vsp5") === 0);
    if (!isDash()) return;

    function ensureLinkCss(){
      const id = "vsp5_shared_css_link_v1";
      if (document.getElementById(id)) return;
      const l = document.createElement("link");
      l.id = id;
      l.rel = "stylesheet";
      l.href = "/static/css/vsp_dark_commercial_p1_2.css";
      l.onload = ()=> console.log("[VSP][theme] shared css loaded");
      l.onerror = ()=> console.warn("[VSP][theme] shared css missing:", l.href);
      (document.head || document.documentElement).appendChild(l);
    }

    function ensureStyle(){
      const id = "vsp5_theme_align_style_v1";
      if (document.getElementById(id)) return;
      const st = document.createElement("style");
      st.id = id;
      st.textContent = `
/* ---- /vsp5 theme align (SAFE MODE) ---- */
:root{
  --vsp-bg: #070e1a;
  --vsp-bg2: #0b1220;
  --vsp-fg: rgba(226,232,240,.96);
  --vsp-muted: rgba(226,232,240,.72);
  --vsp-faint: rgba(226,232,240,.55);
  --vsp-border: rgba(255,255,255,.10);
  --vsp-border2: rgba(255,255,255,.14);
  --vsp-card: rgba(255,255,255,.03);
  --vsp-card2: rgba(255,255,255,.045);
  --vsp-shadow: 0 10px 28px rgba(0,0,0,.42);
}

html, body{
  background: var(--vsp-bg) !important;
  color: var(--vsp-fg) !important;
  font-size: 13px !important;
  line-height: 1.45 !important;
  font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial !important;
}

/* nav top (SAFE MODE html) */
.vsp5nav{
  background: rgba(0,0,0,.26) !important;
  border-bottom: 1px solid var(--vsp-border) !important;
  backdrop-filter: blur(10px);
}
.vsp5nav a{
  color: var(--vsp-fg) !important;
  border: 1px solid var(--vsp-border2) !important;
  background: rgba(255,255,255,.02) !important;
  font-size: 12px !important;
  padding: 8px 10px !important;
  border-radius: 12px !important;
  opacity: .92 !important;
}
.vsp5nav a:hover{
  background: rgba(255,255,255,.06) !important;
  opacity: 1 !important;
}

/* shared components used by injected dashboard */
#vsp_dash_p1_wrap{
  max-width: 1320px;
  margin: 0 auto;
}
#vsp_dash_p1_wrap .vsp_card{
  background: var(--vsp-card) !important;
  border: 1px solid var(--vsp-border) !important;
  border-radius: 16px !important;
  box-shadow: var(--vsp-shadow) !important;
}
#vsp_dash_p1_wrap .vsp_btn{
  color: var(--vsp-fg) !important;
  background: rgba(255,255,255,.035) !important;
  border: 1px solid var(--vsp-border2) !important;
  border-radius: 12px !important;
  font-size: 12px !important;
  padding: 8px 10px !important;
  opacity: .92 !important;
}
#vsp_dash_p1_wrap .vsp_btn:hover{
  opacity: 1 !important;
  filter: brightness(1.08);
}
#vsp_dash_p1_wrap .vsp_pill{
  color: var(--vsp-fg) !important;
  background: rgba(255,255,255,.035) !important;
  border: 1px solid var(--vsp-border2) !important;
  border-radius: 999px !important;
  font-size: 12px !important;
  padding: 6px 8px !important;
  opacity: .92 !important;
}

/* title/labels spacing */
#vsp_dash_p1_wrap .vsp_title{
  font-size: 18px !important;
  font-weight: 800 !important;
  letter-spacing: .2px !important;
}
#vsp_dash_p1_wrap .vsp_subtitle{
  font-size: 12px !important;
  color: var(--vsp-muted) !important;
}
#vsp_dash_p1_wrap .vsp_label{
  font-size: 12px !important;
  color: var(--vsp-muted) !important;
}

/* Gate Story bar: align text a bit */
#vsp5_root, #vsp5_root *{
  color: var(--vsp-fg);
}
      `;
      (document.head || document.documentElement).appendChild(st);
      console.log("[VSP][theme] theme align injected");
    }

    // run
    ensureLinkCss();
    ensureStyle();
  }catch(e){
    console.warn("[VSP][theme] init failed", e);
  }
})();
"""

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended theme align block into gate_story js")
PY

echo "== node --check =="
node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] Open /vsp5 and HARD reload (Ctrl+Shift+R)."
