#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# (1) Replace any template/script include v1 -> v2
python3 - <<'PY'
from pathlib import Path
import re, time

root = Path(".")
tpl = root/"templates"
targets = []
for p in list(tpl.rglob("*.html")) + list((root/"static").rglob("*.html")):
    s = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_bundle_commercial_v1.js" in s:
        targets.append(p)

patched = 0
for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_suffix(p.suffix + f".bak_bundleV2_{int(time.time())}")
    bak.write_text(s, encoding="utf-8")
    s2 = s.replace("vsp_bundle_commercial_v1.js", "vsp_bundle_commercial_v2.js")
    p.write_text(s2, encoding="utf-8")
    patched += 1

print("[OK] templates replaced v1->v2:", patched)
PY

# (2) Make v1 a safe stub (no SyntaxError even if loaded)
V1="static/js/vsp_bundle_commercial_v1.js"
if [ -f "$V1" ]; then
  cp -f "$V1" "$V1.bak_stub_${TS}" || true
  cat > "$V1" <<'JS'
/* VSP_BUNDLE_COMMERCIAL_V1_STUB_P1_V1
   This file was broken (syntax error). Keep as safe stub that loads v2. */
(function(){
  try{
    if (window.__vsp_bundle_commercial_v1_stub) return;
    window.__vsp_bundle_commercial_v1_stub = true;
    var s=document.createElement("script");
    s.src="/static/js/vsp_bundle_commercial_v2.js";
    s.defer=true;
    (document.head||document.documentElement).appendChild(s);
    console.warn("[VSP] v1 bundle stub loaded -> redirected to v2");
  }catch(e){}
})();
JS
  echo "[OK] wrote safe stub: $V1"
else
  echo "[WARN] missing $V1 (skip stub)"
fi

# (3) Sanity: v2 must parse OK
node --check static/js/vsp_bundle_commercial_v2.js >/dev/null
echo "[OK] node --check OK: static/js/vsp_bundle_commercial_v2.js"

echo "[NEXT] restart:"
echo "  sudo systemctl restart vsp-ui-8910.service"
