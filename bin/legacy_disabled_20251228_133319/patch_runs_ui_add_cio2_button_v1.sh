#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_add_cio2_${TS}" && echo "[BACKUP] $F.bak_add_cio2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "run_export_cio_v2" not in s:
    s = re.sub(
        r'(<a class="vsp-btn vsp-btn--ghost" href="\$\{esc\(\"/api/vsp/run_export_cio_v1/\" \+ encodeURIComponent\(rid\) \+ \"\?fmt=html\"\)\}"[^>]*>cio</a>)',
        r'\1\n        <a class="vsp-btn vsp-btn--ghost" href="${esc("/api/vsp/run_export_cio_v2/" + encodeURIComponent(rid) + "?fmt=html")}" target="_blank" rel="noopener">cio2</a>',
        s, count=1
    )

p.write_text(s, encoding="utf-8")
print("[OK] added CIO2 action link (cio2)")
PY

node --check "$F" >/dev/null && echo "[OK] runs JS syntax OK"
echo "[DONE] Runs now has CIO2 button. Hard refresh Ctrl+Shift+R."
