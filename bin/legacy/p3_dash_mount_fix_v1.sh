#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_MOUNT_FIX_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_mountfix_${TS}"
echo "[BACKUP] ${JS}.bak_mountfix_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, textwrap

js_path = sys.argv[1]
mark = sys.argv[2]

p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

block = textwrap.dedent(r"""
/* ===================== VSP_P3_MOUNT_FIX_V1 ===================== */
(function(){
  try{
    if (window.__VSP_MOUNT_FIX_V1__) return;
    window.__VSP_MOUNT_FIX_V1__ = true;

    function isDescendant(parent, child){
      try { return !!(parent && child && parent.contains(child)); } catch(e){ return false; }
    }

    function moveIntoRoot(){
      const root = document.getElementById("vsp5_root");
      if(!root) return;

      const picker = document.getElementById("vsp-run-picker-bar");
      const panel  = document.getElementById("vsp-top-findings-panel");

      // Put them at the top of vsp5_root (under nav), in order: picker -> panel
      const toMove = [];
      if (picker && !isDescendant(root, picker)) toMove.push(picker);
      if (panel  && !isDescendant(root, panel))  toMove.push(panel);

      if (!toMove.length) return;

      // Ensure spacing doesn't look cramped
      root.style.paddingTop = root.style.paddingTop || "8px";

      // Prepend while preserving order
      for (let i = toMove.length - 1; i >= 0; i--){
        root.insertBefore(toMove[i], root.firstChild);
      }
    }

    function boot(){
      // Try several times in case other JS renders late
      let n = 0;
      const t = setInterval(() => {
        n++;
        moveIntoRoot();
        if (n >= 8) clearInterval(t);
      }, 250);
      moveIntoRoot();
    }

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", boot, { once:true });
    } else {
      boot();
    }
  }catch(e){
    try{ console.warn("[MountFixV1] error:", e); }catch(_){}
  }
})();
 /* ===================== /VSP_P3_MOUNT_FIX_V1 ===================== */
""").strip("\n") + "\n"

p.write_text(s.rstrip("\n") + "\n\n" + block, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker in JS =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing in JS"; exit 2; }

echo "[DONE] Mount-fix installed. Open: $BASE/vsp5?rid=VSP_CI_20251215_173713"
