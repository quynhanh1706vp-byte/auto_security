#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) Patch templates: force html/body visible + add an always-visible banner in HTML
python3 - <<'PY'
from pathlib import Path
import time, re
ts=time.strftime("%Y%m%d_%H%M%S")

targets=[Path("templates/vsp_5tabs_enterprise_v2.html"), Path("templates/vsp_dashboard_2025.html")]
force_css = """
<!-- VSP_FORCE_VISIBLE_V1 -->
<style id="VSP_FORCE_VISIBLE_V1">
html,body{display:block !important; visibility:visible !important; opacity:1 !important;}
body{min-height:100vh !important;}
</style>
<div id="VSP_HTML_BANNER_V1" style="position:fixed;bottom:10px;right:10px;z-index:2147483647;
  padding:6px 10px;border-radius:10px;border:1px solid rgba(0,0,0,0.25);
  background:rgba(255,80,80,0.88);color:#111;font:12px ui-monospace,monospace;">
VSP HTML LOADED (force-visible v1)
</div>
"""

for p in targets:
  if not p.exists():
    print("[WARN] missing:", p); continue
  s=p.read_text(encoding="utf-8", errors="replace")
  bak=p.with_name(p.name+f".bak_force_visible_{ts}")
  bak.write_text(s, encoding="utf-8")

  if "VSP_FORCE_VISIBLE_V1" not in s:
    # inject right after <body ...>
    s2=re.sub(r'(<body[^>]*>)', r'\1\n'+force_css, s, count=1, flags=re.I)
    if s2==s:
      s2=s+"\n"+force_css+"\n"
    s=s2

  p.write_text(s, encoding="utf-8")
  print("[OK] patched:", p, "backup:", bak)
PY

# 2) Patch topbar JS: force topbar visible + dark background + log
TB="static/js/vsp_topbar_commercial_v1.js"
if [ -f "$TB" ]; then
  cp -f "$TB" "${TB}.bak_force_topbar_${TS}"
  python3 - <<'PY'
from pathlib import Path
import time
p=Path("static/js/vsp_topbar_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_TOPBAR_FORCE_VISIBLE_V1" in s:
  print("[OK] topbar force already present"); raise SystemExit(0)

addon = """
/* VSP_TOPBAR_FORCE_VISIBLE_V1 */
(() => {
  try{
    const tb = document.querySelector(".vsp-topbar");
    if (tb){
      tb.style.position = "fixed";
      tb.style.top = "0";
      tb.style.left = "0";
      tb.style.right = "0";
      tb.style.zIndex = "2147483647";
      tb.style.background = "rgba(12,16,22,0.92)";
      tb.style.borderBottom = "1px solid rgba(255,255,255,0.10)";
    }
    document.body && (document.body.style.paddingTop = "56px");
    console.info("[VSP][TOPBAR] force-visible v1", "tb=", !!tb, "path=", location.pathname);
  }catch(e){
    console.warn("[VSP][TOPBAR] force-visible error", e);
  }
})();
"""
p.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] appended topbar force-visible:", p)
PY
else
  echo "[WARN] missing $TB (skip topbar patch)"
fi

# 3) Patch KPI v3 JS: add console log + JS banner (so we KNOW it executed)
KPI="static/js/vsp_dashboard_kpi_toolstrip_v3.js"
[ -f "$KPI" ] || { echo "[ERR] missing $KPI"; exit 2; }
cp -f "$KPI" "${KPI}.bak_diag_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_kpi_toolstrip_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_KPI_V3_DIAG_BANNER_V1" in s:
  print("[OK] KPI diag already present"); raise SystemExit(0)

# Insert a log right after the opening (() => { line
s = re.sub(r'\(\(\)\s*=>\s*\{\n', r'(() => {\n  try{ console.info("[VSP][KPI_V3] boot", "path=", location.pathname); }catch(_){ }\n', s, count=1)

# Append a JS banner at end
addon = """
/* VSP_KPI_V3_DIAG_BANNER_V1 */
(() => {
  try{
    const id="VSP_JS_BANNER_V1";
    if (!document.getElementById(id)){
      const b=document.createElement("div");
      b.id=id;
      b.textContent="VSP KPI V3 JS EXECUTED";
      b.setAttribute("style", "position:fixed;bottom:42px;right:10px;z-index:2147483647;" +
        "padding:6px 10px;border-radius:10px;border:1px solid rgba(0,0,0,0.25);" +
        "background:rgba(80,200,120,0.88);color:#111;font:12px ui-monospace,monospace;");
      document.body && document.body.appendChild(b);
    }
  }catch(e){
    try{ console.warn("[VSP][KPI_V3] banner error", e); }catch(_){}
  }
})();
"""
p.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] injected KPI diag banner:", p)
PY

echo "[DONE] force-visible + diag applied."
