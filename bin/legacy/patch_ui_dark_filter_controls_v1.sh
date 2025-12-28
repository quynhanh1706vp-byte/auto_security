#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

for T in templates/vsp_4tabs_commercial_v1.html templates/vsp_dashboard_2025.html; do
  [ -f "$T" ] || continue
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$T" "$T.bak_darkinputs_${TS}"
  echo "[BACKUP] $T.bak_darkinputs_${TS}"

  if grep -q "VSP_DARK_FILTER_CONTROLS_V1" "$T"; then
    echo "[OK] $T already patched, skip"
    continue
  fi

  python3 - <<PY
from pathlib import Path
import re
p=Path("$T")
s=p.read_text(encoding="utf-8", errors="ignore")
css = r'''
<style id="VSP_DARK_FILTER_CONTROLS_V1">
/* commercial dark: stop white inputs/selects */
select, input[type="text"], input[type="number"], input[type="search"], textarea {
  background: rgba(15, 23, 42, 0.65) !important;
  color: rgba(255,255,255,0.92) !important;
  border: 1px solid rgba(148,163,184,0.22) !important;
  outline: none !important;
}
select option { background: #0b1220 !important; color: rgba(255,255,255,0.92) !important; }
input::placeholder, textarea::placeholder { color: rgba(148,163,184,0.75) !important; }
</style>
'''
if "</head>" in s:
    s=s.replace("</head>", css+"\n</head>")
else:
    s = css + "\n" + s
p.write_text(s, encoding="utf-8")
print("[OK] injected dark filter controls CSS ->", p)
PY
done

echo "[DONE] patched templates. NEXT: hard refresh (Ctrl+Shift+R)"
