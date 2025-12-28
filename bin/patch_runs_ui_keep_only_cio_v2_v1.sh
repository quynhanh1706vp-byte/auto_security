#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_only_cio_v2_${TS}" && echo "[BACKUP] $F.bak_only_cio_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) If there is a cio2 button, remove it (keep formatting)
s = re.sub(r'\n\s*<a class="vsp-btn vsp-btn--ghost" href="\$\{esc\(\"/api/vsp/run_export_cio_v2/\" \+ encodeURIComponent\(rid\) \+ "\?fmt=html\"\)\}"[^>]*>cio2</a>\s*', '\n', s)

# 2) Replace cio v1 route -> cio v2 route (keep label "cio")
s = re.sub(
  r'"/api/vsp/run_export_cio_v1/"\s*\+\s*encodeURIComponent\(rid\)\s*\+\s*"\?fmt=html"',
  r'"/api/vsp/run_export_cio_v2/" + encodeURIComponent(rid) + "?fmt=html"',
  s
)

p.write_text(s, encoding="utf-8")
print("[OK] kept only CIO (v2 route) in Runs")
PY

node --check "$F" >/dev/null && echo "[OK] runs JS syntax OK"
echo "[DONE] Runs now shows only CIO (v2). Hard refresh Ctrl+Shift+R."
