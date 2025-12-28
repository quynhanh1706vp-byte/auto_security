#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_charts_pretty_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_dispatch_${TS}"
echo "[BACKUP] $F.bak_fix_dispatch_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_dashboard_charts_pretty_v3.js")
t = p.read_text(encoding="utf-8", errors="ignore")

# 1) Remove ONLY the broken "charts-ready dispatch" block that got injected INSIDE the object literal.
#    (We search for vsp:charts-ready inside our tag block and remove that block.)
pat = re.compile(
    r"// === VSP_PRETTY_V3_READY_AUTOCANVAS_V1 ===\s*[\s\S]*?vsp:charts-ready[\s\S]*?// === END VSP_PRETTY_V3_READY_AUTOCANVAS_V1 ===\s*",
    re.M
)
t2, n = pat.subn("", t, count=1)
if n:
    print(f"[OK] removed broken dispatch block (n={n})")
    t = t2
else:
    print("[INFO] no broken dispatch block found (maybe already removed)")

# 2) Add a safe dispatch block OUTSIDE the object (near end, before closing IIFE if present).
TAG2 = "// === VSP_PRETTY_V3_CHARTS_READY_DISPATCH_V1 ==="
if TAG2 in t:
    print("[OK] safe dispatch block already present")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

safe = r"""
// === VSP_PRETTY_V3_CHARTS_READY_DISPATCH_V1 ===
try {
  // announce that charts engine has been registered
  window.dispatchEvent(new CustomEvent('vsp:charts-ready', { detail: { engine: 'V3' } }));
  console.log('[VSP_CHARTS_V3] dispatched vsp:charts-ready (SAFE)');
} catch(e) {}
// === END VSP_PRETTY_V3_CHARTS_READY_DISPATCH_V1 ===
"""

# Insert before a closing IIFE if we can find it, otherwise append.
# Common endings: "})();" or "}());"
m = re.search(r"\n\s*\}\)\s*;\s*\n?\s*$", t)  # "});" end
if not m:
    m = re.search(r"\n\s*\}\s*\)\s*\(\s*\)\s*;\s*\n?\s*$", t)  # "}() ;" variants

# More robust: search last occurrence of "})();" or "}());"
idx = max(t.rfind("})();"), t.rfind("}());"))
if idx != -1:
    t = t[:idx] + "\n" + safe + "\n" + t[idx:]
    print("[OK] inserted safe dispatch before IIFE close")
else:
    t = t.rstrip() + "\n\n" + safe + "\n"
    print("[OK] appended safe dispatch at EOF")

p.write_text(t, encoding="utf-8")
print("[OK] wrote file")
PY

echo "== node --check =="
node --check "$F"
echo "[OK] done"
