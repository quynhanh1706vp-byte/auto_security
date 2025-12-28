#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

BUNDLE="static/js/vsp_bundle_commercial_v2.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_ridloader_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_ridloader_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P0_RID_AUTOFIX_LOADER_V1"
if marker in s:
    print("[OK] loader already present")
    raise SystemExit(0)

loader = r"""
/* VSP_P0_RID_AUTOFIX_LOADER_V1 */
(()=> {
  try{
    if (window.__vsp_p0_rid_autofix_loader_v1) return;
    window.__vsp_p0_rid_autofix_loader_v1 = true;
    if (document.querySelector('script[src*="vsp_rid_autofix_v1.js"]')) return;

    let v = "";
    try{
      const me = Array.from(document.scripts).map(x=>x.src||"").find(u=>u.includes("vsp_bundle_commercial_v2.js"));
      const m = me && me.match(/[?&]v=([^&]+)/);
      v = (m && m[1]) ? m[1] : "";
    }catch(e){}
    if (!v) v = String(Date.now());

    const sc = document.createElement("script");
    sc.src = "/static/js/vsp_rid_autofix_v1.js?v=" + encodeURIComponent(v);
    sc.defer = true;
    document.head.appendChild(sc);
  }catch(e){}
})();
"""
p.write_text(loader.lstrip("\n") + "\n" + s, encoding="utf-8")
print("[OK] inserted loader at top of bundle")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$BUNDLE" && echo "[OK] node --check bundle OK"
fi
