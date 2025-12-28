#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

echo "== write containers-fix JS =="
JS="static/js/vsp_dashboard_containers_fix_v1.js"
cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
/* VSP_P0_CONTAINERS_FIX_V1
   Ensures DashCommercial containers exist so dashboard doesn't warn "missing containers".
*/
(() => {
  if (window.__vsp_p0_containers_fix_v1) return;
  window.__vsp_p0_containers_fix_v1 = true;

  const IDS = ["vsp-chart-severity","vsp-chart-trend","vsp-chart-bytool","vsp-chart-topcve"];

  function ensure(){
    try{
      // Prefer legacy root first (because bundle renderer expects it),
      // otherwise use luxe host, otherwise body.
      const root =
        document.querySelector("#vsp5_root") ||
        document.querySelector("#vsp_luxe_host") ||
        document.body;

      if (!root) return;

      let shell = document.querySelector("#vsp5_dash_shell");
      if (!shell){
        shell = document.createElement("div");
        shell.id = "vsp5_dash_shell";
        // non-intrusive layout: does not break existing UI; just provides containers.
        shell.style.cssText = "padding:12px 14px; display:grid; grid-template-columns: 1fr 1fr; gap:12px;";
        // Insert near top of root so charts have stable place.
        root.prepend(shell);
      }

      for (const id of IDS){
        if (document.getElementById(id)) continue;
        const d = document.createElement("div");
        d.id = id;
        // give min height so charts have space but not too big
        d.style.cssText = "min-height:160px;";
        shell.appendChild(d);
      }
    }catch(e){}
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ensure);
  } else {
    ensure();
  }

  // In case renderer wipes DOM, re-ensure shortly after load.
  setTimeout(ensure, 800);
})();
JS

echo "[OK] wrote $JS"

echo "== patch bundle_tag in $WSGI to include containers-fix + luxe (safe single-line) =="
cp -f "$WSGI" "${WSGI}.bak_contfix_${TS}"
echo "[BACKUP] ${WSGI}.bak_contfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Build a safe single-line f-string for bundle_tag
safe_line = (
  "bundle_tag = f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={v}\"></script>\\n"
  "<script src=\"/static/js/vsp_dashboard_containers_fix_v1.js?v={v}\"></script>\\n"
  "<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={v}\"></script>'"
)

# Replace any existing bundle_tag assignment that references vsp_bundle_commercial_v2.js
pat = re.compile(r'^(\s*)bundle_tag\s*=\s*.*vsp_bundle_commercial_v2\.js.*$', re.M)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find bundle_tag assignment referencing vsp_bundle_commercial_v2.js")

indent = m.group(1)
s2 = pat.sub(indent + safe_line, s, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] patched bundle_tag to include containers_fix + luxe")
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 must include both scripts =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_containers_fix_v1.js" | head -n 2
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 2
echo "[DONE] Ctrl+Shift+R on /vsp5"
