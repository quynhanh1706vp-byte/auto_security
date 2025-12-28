#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_dashboard_2025.html"
CSS="static/css/vsp_dashboard_polish_v1.css"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_polish_${TS}"
echo "[BACKUP] ${TPL}.bak_polish_${TS}"

mkdir -p "$(dirname "$CSS")"
cat > "$CSS" <<'CSS'
/* VSP_DASHBOARD_POLISH_V1 - cosmetics only (no contract/API changes) */

:root{
  --vsp-bg: #070e1a;
  --vsp-panel: rgba(12, 18, 33, 0.72);
  --vsp-border: rgba(120, 140, 170, 0.16);
  --vsp-text: rgba(232, 238, 255, 0.92);
  --vsp-muted: rgba(200, 212, 240, 0.60);
  --vsp-shadow: 0 10px 30px rgba(0,0,0,0.30);
}

/* Center and reduce awkward empty space */
html,body{ background: var(--vsp-bg) !important; color: var(--vsp-text) !important; }
main, .main, #main, .container, .page, .vsp-page, #app, .app {
  max-width: 1320px;
  margin: 0 auto;
}
main, .main, #main, .container, .page, .vsp-page { padding: 14px 16px !important; }

/* Make cards consistent */
.card, .panel, [class*="card"], [class*="panel"]{
  border-radius: 16px !important;
  border: 1px solid var(--vsp-border) !important;
  background: var(--vsp-panel) !important;
  box-shadow: var(--vsp-shadow) !important;
  backdrop-filter: blur(8px);
}

/* Buttons look premium */
button, .btn, a.btn, [class*="btn"]{
  border-radius: 999px !important;
  border: 1px solid rgba(130,160,200,0.20) !important;
}
button:hover, .btn:hover, a.btn:hover{
  border-color: rgba(170,210,255,0.35) !important;
}

/* Typography */
h1,h2,h3{ letter-spacing: .2px; }
.small, .muted, [class*="muted"]{ color: var(--vsp-muted) !important; }

/* Hide obvious debug / placeholder blocks if they are still in DOM */
.vsp-debug, .vsp-debug-box, .vsp-contract, .vsp-hint, .vsp-fetch, .vsp-legacy-killed{
  display:none !important;
}
CSS
echo "[OK] wrote $CSS"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DASHBOARD_POLISH_LUNGLINH_V1"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

# 1) ensure polish css included (after main css)
link = r'<link rel="stylesheet" href="/static/css/vsp_dashboard_polish_v1.css?v={{ asset_v|default(\'\') }}"/>'
if "vsp_dashboard_polish_v1.css" not in s:
    # Insert after any existing css link
    s = re.sub(r'(<link[^>]+href="/static/css/[^"]+\.css[^"]*"[^>]*>\s*)',
               r'\1' + link + "\n",
               s, count=1, flags=re.I) or s
    if "vsp_dashboard_polish_v1.css" not in s:
        # fallback: inside <head>
        s = re.sub(r'(<head[^>]*>)', r'\1\n' + link + "\n", s, count=1, flags=re.I)

# 2) inject JS to hide debug boxes by TEXT (robust) + MutationObserver
js = r"""
<!-- VSP_P1_DASHBOARD_POLISH_LUNGLINH_V1 -->
<script>
(()=>{ try{
  const NEEDLES = [
    "VSP fetch", "Data contract", "ISO quick hint", "mapping", "placeholder",
    "legacy disabled", "containers/rid missing", "Chart/container missing"
  ];

  const looksDebug = (el)=>{
    try{
      const t = (el.innerText||"").trim();
      if (!t) return false;
      // Require at least 1 needle + small-ish box, OR fixed overlay
      const hit = NEEDLES.some(n => t.includes(n));
      if (!hit) return false;
      const st = window.getComputedStyle(el);
      const fixed = st && (st.position === "fixed" || st.position === "sticky");
      const small = (el.offsetHeight <= 240 && el.offsetWidth <= 520);
      return fixed || small;
    }catch(_){ return false; }
  };

  const kill = ()=>{
    const nodes = document.querySelectorAll("div,section,article,aside");
    let n=0;
    for (const el of nodes){
      if (el.__vsp_polish_killed) continue;
      if (looksDebug(el)){
        el.__vsp_polish_killed = true;
        el.classList.add("vsp-debug-box");
        try{ el.remove(); }catch(_){}
        n++;
      }
    }
    if (n) console.log("[VSP][POLISH] removed debug boxes:", n);
  };

  kill();
  setTimeout(kill, 250);
  setTimeout(kill, 900);
  const mo = new MutationObserver(()=>kill());
  mo.observe(document.documentElement, {subtree:true, childList:true});
}catch(_){}})();
</script>
<!-- /VSP_P1_DASHBOARD_POLISH_LUNGLINH_V1 -->
"""

if MARK not in s:
    # Insert near end of head for early apply
    s = re.sub(r'(</head>)', js + r"\n\1", s, count=1, flags=re.I)
    s = s.replace("<!-- VSP_P1_DASHBOARD_POLISH_LUNGLINH_V1 -->", f"<!-- {MARK} -->", 1)

tpl.write_text(s, encoding="utf-8")
print("[OK] patched template for polish + hide debug boxes")
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
