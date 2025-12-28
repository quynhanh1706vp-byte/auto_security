#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_dashboard_2025.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_gate_mount_${TS}"
echo "[BACKUP] $T.bak_gate_mount_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("templates/vsp_dashboard_2025.html")
t = p.read_text(encoding="utf-8", errors="ignore")

if 'id="vsp_gate_panel"' in t:
    print("[OK] gate mount already exists")
    raise SystemExit(0)

# insert mount right before gate js include
pat = r'(<script\s+src="/static/js/vsp_gate_panel_v1\.js[^"]*"\s+defer></script>)'
m = re.search(pat, t, flags=re.I)
if not m:
    print("[ERR] cannot find vsp_gate_panel_v1.js script tag to anchor")
    raise SystemExit(2)

mount = '\n<!-- VSP_GATE_MOUNT_P0 -->\n<div id="vsp_gate_panel"></div>\n'
t2 = t[:m.start()] + mount + t[m.start():]

p.write_text(t2, encoding="utf-8")
print("[OK] inserted <div id=\"vsp_gate_panel\"></div> before gate script include")
PY

echo "[OK] patched template gate mount"
echo "[NEXT] restart UI + hard refresh"
