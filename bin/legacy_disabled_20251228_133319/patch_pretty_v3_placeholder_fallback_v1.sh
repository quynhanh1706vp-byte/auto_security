#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_charts_pretty_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_placeholder_fallback_${TS}"
echo "[BACKUP] $F.bak_placeholder_fallback_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_dashboard_charts_pretty_v3.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_PRETTY_V3_PLACEHOLDER_FALLBACK_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# Find the helper function that scans candidates and returns null
# We anchor on the known line: document.getElementById(candidates[i])
pat = re.compile(r"""
(function\s+\w+\s*\(\s*candidates\s*\)\s*\{[\s\S]*?
document\.getElementById\(candidates\[i\]\)[\s\S]*?)
(\breturn\s+null\s*;)
""", re.VERBOSE)

m = pat.search(t)
if not m:
    raise SystemExit("[ERR] cannot find candidates->getElementById helper to patch")

inject = r"""
  // === VSP_PRETTY_V3_PLACEHOLDER_FALLBACK_V1 ===
  // Commercial template uses placeholder DIVs: vsp-chart-severity/trend/bytool/topcwe
  try {
    var joined = (candidates || []).join(' ').toLowerCase();
    var pid = null;
    if (joined.includes('sever')) pid = 'vsp-chart-severity';
    else if (joined.includes('trend')) pid = 'vsp-chart-trend';
    else if (joined.includes('bytool') || joined.includes('tool')) pid = 'vsp-chart-bytool';
    else if (joined.includes('cwe')) pid = 'vsp-chart-topcwe';

    if (pid) {
      var box = document.getElementById(pid);
      if (box) {
        var cv = box.querySelector('canvas');
        if (!cv) {
          cv = document.createElement('canvas');
          cv.style.width = '100%';
          cv.style.height = '100%';
          // keep responsive sizing
          cv.width  = box.clientWidth  || 800;
          cv.height = box.clientHeight || 220;
          box.innerHTML = '';
          box.appendChild(cv);
        }
        return cv;
      }
    }
  } catch (e) {}
"""

t2 = t[:m.start(2)] + inject + "\n  " + t[m.start(2):]

p.write_text(t2, encoding="utf-8")
print("[OK] injected placeholder fallback into candidates helper")
PY

node --check "$F"
echo "[OK] node --check passed"
