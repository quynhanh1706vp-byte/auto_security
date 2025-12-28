#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

targets=(static/js/vsp_dashboard_commercial_v1.js static/js/vsp_dash_only_v1.js)
for JS in "${targets[@]}"; do
  [ -f "$JS" ] || continue
  cp -f "$JS" "${JS}.bak_uibadgefix_${TS}"
  echo "[BACKUP] ${JS}.bak_uibadgefix_${TS}"

  python3 - <<PY
from pathlib import Path
import re, textwrap

p = Path("$JS")
s = p.read_text(encoding="utf-8", errors="replace")

# replace prior badge block (v1) if exists
s2 = re.sub(r"/\*\s*====================\s*VSP_P1_UI_OK_BADGE_V1\s*====================\s*\*/.*?/\*\s*====================\s*/VSP_P1_UI_OK_BADGE_V1\s*====================\s*\*/",
            "", s, flags=re.S)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_UI_OK_BADGE_V2_FORCE_FIXED ===================== */
(()=> {
  if (window.__vsp_p1_ui_ok_badge_v2) return;
  window.__vsp_p1_ui_ok_badge_v2 = true;

  async function ping(){
    try{
      const r = await fetch("/api/vsp/rid_latest_gate_root", {credentials:"same-origin"});
      if(!r.ok) return {ok:false, status:r.status};
      const j = await r.json().catch(()=>null);
      return {ok: !!(j && (j.ok || j.rid)), status:200};
    }catch(e){
      return {ok:false, status:0};
    }
  }

  function mount(){
    let b = document.getElementById("vsp_ui_ok_badge_v2");
    if (!b){
      b = document.createElement("div");
      b.id = "vsp_ui_ok_badge_v2";
      b.style.cssText =
        "position:fixed;z-index:999999;top:10px;right:12px;" +
        "display:inline-flex;align-items:center;gap:8px;" +
        "padding:6px 12px;border-radius:999px;" +
        "border:1px solid rgba(255,255,255,.12);" +
        "background:rgba(10,18,32,.82);" +
        "backdrop-filter: blur(10px);" +
        "color:#d8ecff;font:12px/1.2 system-ui,Segoe UI,Roboto;" +
        "box-shadow:0 10px 30px rgba(0,0,0,.35)";
      b.textContent = "UI: …";
      document.body.appendChild(b);
    }

    async function refresh(){
      const res = await ping();
      if(res.ok){
        b.textContent = "UI: OK";
        b.style.borderColor = "rgba(90,255,170,.35)";
        b.style.background = "rgba(20,80,40,.35)";
        b.style.color = "#c9ffe0";
      } else {
        b.textContent = "UI: DEGRADED";
        b.style.borderColor = "rgba(255,210,120,.35)";
        b.style.background = "rgba(80,60,20,.35)";
        b.style.color = "#ffe7b7";
      }
    }
    refresh();
    setInterval(refresh, 20000);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
/* ===================== /VSP_P1_UI_OK_BADGE_V2_FORCE_FIXED ===================== */
""")

p.write_text(s2 + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] badge v2 force-fixed written:", p)
PY

  if command -v node >/dev/null 2>&1; then node --check "$JS" >/dev/null && echo "[OK] node --check $JS"; fi
done

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] badge v2 force-fixed applied + restarted $SVC"
