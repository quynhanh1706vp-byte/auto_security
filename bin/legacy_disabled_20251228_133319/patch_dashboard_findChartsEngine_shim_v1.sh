#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_charts_shim_${TS}"
echo "[BACKUP] $F.bak_charts_shim_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_enhance_v1.js")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_CHARTS_ENGINE_SHIM_V1 ==="
if TAG in txt:
    print("[OK] already patched"); raise SystemExit(0)

shim = r"""
// === VSP_CHARTS_ENGINE_SHIM_V1 ===
(function(){
  // Always provide a safe resolver so dashboard never crashes on missing symbol names.
  function _findChartsEngineShim(){
    return (
      window.VSP_CHARTS_ENGINE_V3 ||
      window.VSP_CHARTS_V3 ||
      window.VSP_CHARTS_PRETTY_V3 ||
      window.VSP_DASH_CHARTS_V3 ||
      window.VSP_CHARTS_ENGINE_V2 ||
      window.VSP_CHARTS_V2 ||
      window.VSP_CHARTS_ENGINE ||
      window.VSP_CHARTS ||
      null
    );
  }
  if (typeof window.findChartsEngine !== 'function') {
    window.findChartsEngine = _findChartsEngineShim;
  }
})();
"""

# Cắm shim ngay đầu file (sau comment header nếu có)
out = shim.strip() + "\n\n" + txt
p.write_text(out, encoding="utf-8")
print("[OK] inserted shim into", p)
PY

echo "== node --check =="
node --check "$F"
