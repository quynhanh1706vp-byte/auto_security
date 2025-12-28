#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_killreload_${TS}"
echo "[BACKUP] ${JS}.bak_killreload_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_KILL_RELOAD_LOOP_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    pre = r"""/* ===================== VSP_P0_KILL_RELOAD_LOOP_V1 =====================
   Hard stop any reload/redirect loops that make /vsp5 look "đơ".
   (run at TOP of bundle)
======================================================================= */
(()=>{ try{
  if (window.__vsp_p0_kill_reload_loop_v1) return;
  window.__vsp_p0_kill_reload_loop_v1 = true;

  const href = (location && location.href) ? String(location.href) : "";
  const isVsp5 = href.includes("/vsp5");
  if (!isVsp5) return;

  console.warn("[VSP][KILL_RELOAD_V1] active on", href);

  // 1) Disable location.reload
  try{
    const orig = window.location.reload.bind(window.location);
    window.__vsp_orig_reload = orig;
    window.location.reload = function(){
      console.warn("[VSP][KILL_RELOAD_V1] location.reload() blocked");
    };
  }catch(e){ console.error("[VSP][KILL_RELOAD_V1] patch reload err", e); }

  // 2) Block direct assignment redirects (best-effort)
  try{
    const _assign = window.location.assign.bind(window.location);
    const _replace = window.location.replace.bind(window.location);
    window.location.assign = function(u){
      console.warn("[VSP][KILL_RELOAD_V1] location.assign blocked:", u);
    };
    window.location.replace = function(u){
      console.warn("[VSP][KILL_RELOAD_V1] location.replace blocked:", u);
    };
    window.__vsp_orig_assign = _assign;
    window.__vsp_orig_replace = _replace;
  }catch(e){}

  // 3) Stop meta refresh if any (rare)
  try{
    document.querySelectorAll('meta[http-equiv="refresh"]').forEach(m=>{
      console.warn("[VSP][KILL_RELOAD_V1] removing meta refresh");
      m.remove();
    });
  }catch(e){}

} catch(e){ console.error("[VSP][KILL_RELOAD_V1] fatal", e); } })();
/* ===================== /VSP_P0_KILL_RELOAD_LOOP_V1 ===================== */
"""
    p.write_text(pre + "\n\n" + s, encoding="utf-8")
    print("[OK] inserted at TOP:", MARK)
PY

node --check static/js/vsp_dash_only_v1.js >/dev/null
echo "[OK] node --check passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Ctrl+Shift+R /vsp5 then open Console -> should see [VSP][KILL_RELOAD_V1] active"
