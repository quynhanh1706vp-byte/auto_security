#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_fixquote_${TS}"
echo "[BACKUP] ${WSGI}.bak_fixquote_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

out = []
fixed = 0

for line in lines:
    if "vsp_dashboard_commercial_panels_v1.js" in line:
        indent = line[:len(line) - len(line.lstrip())]
        # Write a SAFE python string line (double-quoted outer, escaped inner quotes)
        # Keep {asset_v} literal if exists; if not present in original, still fine.
        repl = indent + "\"  <script src=\\\"/static/js/vsp_dashboard_commercial_panels_v1.js?v={asset_v}\\\"></script>\\\\n\""
        # preserve comma if context is list/tuple of strings
        if not line.rstrip().endswith(","):
            repl += ","
        repl += "\n"
        out.append(repl)
        fixed += 1
    else:
        out.append(line)

if fixed == 0:
    print("[WARN] no panels line found; nothing changed.")
else:
    p.write_text("".join(out), encoding="utf-8")
    print(f"[OK] fixed panels script line(s): {fixed}")

PY

python3 -m py_compile "$WSGI" && echo "[OK] py_compile WSGI OK"

echo
echo "[NEXT] restart UI service rồi Ctrl+Shift+R /vsp5"
echo "[VERIFY] curl /vsp5 includes panels:"
echo "  curl -fsS http://127.0.0.1:8910/vsp5 | grep -n 'commercial_panels_v1' || true"
