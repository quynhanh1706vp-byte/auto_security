#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_stray_blockend_${TS}"
echo "[BACKUP] ${JS}.bak_fix_stray_blockend_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dash_only_v1.js")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

changed = 0
# Comment-out standalone stray block-comment ends: "*/"
# (this exact pattern is what's killing node --check)
for i, l in enumerate(lines):
    s = l.strip()
    if s == "*/":
        # keep indentation
        indent = re.match(r"^(\s*)", l).group(1)
        lines[i] = f"{indent}// */  /* auto-fix: stray block-comment end */\n"
        changed += 1

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] fixed stray '*/' lines: {changed}")
PY

echo "== [1] node --check after fix =="
node --check "$JS"

echo "== [2] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
