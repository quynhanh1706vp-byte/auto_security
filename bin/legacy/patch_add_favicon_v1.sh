#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_dashboard_2025.html"
mkdir -p static

# create a tiny favicon if missing
if [ ! -f static/favicon.ico ]; then
  python3 - <<'PY'
from pathlib import Path
# minimal 1x1 ico-like placeholder (not perfect but browsers accept)
Path("static/favicon.ico").write_bytes(b"\x00\x00\x01\x00\x01\x00\x01\x01\x00\x00\x01\x00\x18\x00\x16\x00\x00\x00\x16\x00\x00\x00" + b"\x00"*22)
print("[OK] wrote static/favicon.ico")
PY
fi

cp -f "$TPL" "$TPL.bak_favicon_${TS}" && echo "[BACKUP] $TPL.bak_favicon_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time
p=Path("templates/vsp_dashboard_2025.html")
html=p.read_text(encoding="utf-8", errors="ignore")
if "rel=\"icon\"" in html or "favicon.ico" in html:
    print("[OK] favicon link already present")
else:
    tag = f'<link rel="icon" href="/static/favicon.ico?v={int(time.time())}"/>'
    m=re.search(r'<head[^>]*>', html, flags=re.I)
    if m:
        i=m.end()
        html = html[:i] + "\n  " + tag + "\n" + html[i:]
    else:
        html = tag + "\n" + html
    p.write_text(html, encoding="utf-8")
    print("[OK] injected favicon link")
PY

bash bin/ui_restart_8910_no_restore_v1.sh
echo "[NEXT] Ctrl+Shift+R, check console (favicon 404 should be gone)."
