#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p72b_${TS}"
echo "[OK] backup ${F}.bak_p72b_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P72B_LOAD_DASHBOARD_MAIN_V1"
if marker in s:
    print("[OK] already patched P72B")
    raise SystemExit(0)

inject=r"""
/* VSP_P72B_LOAD_DASHBOARD_MAIN_V1 */
(function(){
  try{
    var scripts = Array.prototype.slice.call(document.scripts || []);
    var has = scripts.some(function(sc){ return sc && sc.src && sc.src.indexOf("vsp_dashboard_main_v1.js")>=0; });
    if (has) return;

    var sc = document.createElement("script");
    sc.src = "/static/js/vsp_dashboard_main_v1.js?v=" + Date.now();
    sc.async = true;
    sc.onload = function(){ console.info("[VSP] dashboard_main_v1 loaded (P72B)"); };
    sc.onerror = function(e){ console.warn("[VSP] dashboard_main_v1 load FAILED (P72B)", e); };
    document.head.appendChild(sc);
  }catch(e){}
})();
"""
s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] P72B appended loader for dashboard_main_v1")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P72B applied. Hard refresh: Ctrl+Shift+R"
