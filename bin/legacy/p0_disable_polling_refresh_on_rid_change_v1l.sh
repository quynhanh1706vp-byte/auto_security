#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

FILES=(
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_tabs3_common_v3.js
)

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { warn "missing: $f"; continue; }
  cp -f "$f" "${f}.bak_nopoll_${TS}"
  ok "backup: ${f}.bak_nopoll_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P0_NO_POLL_REFRESH_ON_RID_CHANGE_V1L"

def inject_guard(src: str) -> str:
  if MARK in src:
    return src
  guard = r'''
/* ===================== VSP_P0_NO_POLL_REFRESH_ON_RID_CHANGE_V1L =====================
   Purpose: stop timer polling that causes XHR spam; refresh only when RID changes.
   Strategy:
   - Wrap setInterval for known polling intervals (>=2000ms) to no-op.
   - Provide a lightweight rid-change notifier.
=============================================================================== */
(function(){
  try{
    if (window.__VSP_NO_POLL_V1L__) return;
    window.__VSP_NO_POLL_V1L__ = true;

    // 1) Disable long polling intervals (keep short UI animation timers)
    const _setInterval = window.setInterval.bind(window);
    window.setInterval = function(fn, ms){
      try{
        const t = Number(ms||0);
        if (t >= 2000){
          // no-op: return a fake id
          return 0;
        }
      }catch(e){}
      return _setInterval(fn, ms);
    };

    // 2) RID change detection
    function getRid(){
      try{ return (new URL(location.href)).searchParams.get("rid") || ""; }catch(e){ return ""; }
    }
    let last = getRid();

    function notify(){
      try{
        const cur = getRid();
        if (cur && cur !== last){
          last = cur;
          // fire a soft event so tabs can re-render if they want
          window.dispatchEvent(new CustomEvent("vsp:rid_changed", { detail: { rid: cur } }));
        }
      }catch(e){}
    }

    // Hook history changes + popstate
    const _push = history.pushState;
    history.pushState = function(){
      const r = _push.apply(this, arguments);
      notify();
      return r;
    };
    const _replace = history.replaceState;
    history.replaceState = function(){
      const r = _replace.apply(this, arguments);
      notify();
      return r;
    };
    window.addEventListener("popstate", notify);

  }catch(e){}
})();
'''
  return guard + "\n\n" + src

def remove_obvious_polling(src: str) -> str:
  x = src
  # Neutralize common polling function names (defensive, doesn't break if not present)
  # Replace patterns like setInterval(loadXxx, 3000) -> (disabled by wrapper anyway)
  # Also drop any "?ts=" + Date.now() churn if still present
  x = x.replace('?ts=" + Date.now()', '"')
  x = x.replace("?ts=' + Date.now()", "'")
  x = x.replace("&ts=" + "Date.now()", "")
  return x

targets = ["static/js/vsp_tabs4_autorid_v1.js", "static/js/vsp_tabs3_common_v3.js"]
for t in targets:
  p = Path(t)
  if not p.exists():
    continue
  s = p.read_text(encoding="utf-8", errors="ignore")
  s2 = inject_guard(remove_obvious_polling(s))
  if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", t)
  else:
    print("[OK] nochange:", t)
PY

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  node --check "$f" && ok "node --check OK: $f" || err "node --check FAIL: $f"
done

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [DONE] Reload /vsp5 (Ctrl+F5). Polling intervals >=2s are now disabled. =="
