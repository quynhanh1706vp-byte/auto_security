#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_lazyfind_v2_${TS}"
echo "[BACKUP] ${JS}.bak_lazyfind_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) widen gesture window 2s -> 12s
s2, n1 = re.subn(r'\(now - __lastGesture\)\s*<\s*2000', r'(now - __lastGesture) < 12000', s)

# 2) allow big findings when on /data_source
# inject: const onDataSource = (location.pathname||"").includes("data_source");
if "const onDataSource" not in s2:
    s2, n2 = re.subn(
        r'const shouldGate\s*=\s*\(url\)\s*=>\s*\{',
        'const shouldGate = (url) => {\n      const onDataSource = ((location && location.pathname) ? location.pathname : "").includes("data_source");\n      if (onDataSource) return false;',
        s2,
        count=1
    )
else:
    n2 = 0

if n1 == 0 and n2 == 0:
    print("[WARN] no changes applied (patterns not found).")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] updated bundle:", p, "n1=", n1, "n2=", n2)
PY

command -v node >/dev/null 2>&1 && node --check "$JS" && echo "[OK] node --check passed" || true
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] lazy-load v2 applied."
