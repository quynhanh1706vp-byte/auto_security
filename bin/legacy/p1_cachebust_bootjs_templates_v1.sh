#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - "$TS" <<'PY'
import sys, re
from pathlib import Path
ts=sys.argv[1]

tpl=Path("templates")
changed=[]
for p in tpl.rglob("*.html"):
    s=p.read_text(encoding="utf-8", errors="replace")
    if "vsp_p1_page_boot_v1.js" not in s:
        continue
    s2=re.sub(r'vsp_p1_page_boot_v1\.js(\?v=[0-9_]+)?', f'vsp_p1_page_boot_v1.js?v={ts}', s)
    if s2!=s:
        p.write_text(s2, encoding="utf-8")
        changed.append(str(p))
print(f"[OK] cachebust updated templates: {len(changed)}")
for x in changed[:30]:
    print(" -", x)
PY

echo "[OK] restart UI"
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1

echo "== verify template includes cache-bust =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -o 'vsp_p1_page_boot_v1.js[^"]*' | head -n 5 || true
