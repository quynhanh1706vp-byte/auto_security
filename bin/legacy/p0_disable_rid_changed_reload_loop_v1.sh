#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_disable_reload_${TS}"
echo "[BACKUP] ${JS}.bak_disable_reload_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_DISABLE_RID_RELOAD_LOOP_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Safest: add a hard guard at top-level to prevent reload storms.
guard = r"""
/* VSP_P0_DISABLE_RID_RELOAD_LOOP_V1: prevent reload storms */
(()=> {
  try{
    if (window.__vsp_disable_rid_reload_loop_v1) return;
    window.__vsp_disable_rid_reload_loop_v1 = true;
    const KEY="__vsp_rid_reload_once_v1";
    const oldReload = window.location.reload.bind(window.location);
    window.location.reload = function(){
      try{
        if (sessionStorage.getItem(KEY)) {
          console.warn("[VSP] reload suppressed (loop guard)");
          return;
        }
        sessionStorage.setItem(KEY,"1");
      }catch(_){}
      return oldReload();
    };
  }catch(_){}
})();
"""
p.write_text(s + "\n\n" + guard + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check static/js/vsp_dash_only_v1.js
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5."
