#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need systemctl

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_nodashreload_${TS}"
echo "[BACKUP] ${JS}.bak_nodashreload_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Patch only inside SAFEAPPEND block by replacing the reload condition
# Old: if (pth === "/vsp5" || pth.includes("dashboard")) location.reload();
# New: only reload if NOT /vsp5 (and not dashboard)
s2, n = re.subn(
    r'if\s*\(\s*pth\s*===\s*"\/vsp5"\s*\|\|\s*pth\.includes\("dashboard"\)\s*\)\s*location\.reload\(\)\s*;',
    r'if (pth !== "/vsp5" && !pth.includes("dashboard")) location.reload();',
    s
)

if n == 0:
    # fallback: conservative, just no-op the reload line in that block
    s2, n2 = re.subn(r'location\.reload\(\)\s*;', r'/* dashboard-safe: no reload */', s, count=1)
    if n2 == 0:
        raise SystemExit("[ERR] cannot patch reload condition")

p.write_text(s2, encoding="utf-8")
print("[OK] patched: disable dashboard reload")
PY

node --check "$JS"
echo "[OK] node --check"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"
