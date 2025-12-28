#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_hide_promote_${TS}"
echo "[BACKUP] ${W}.bak_hide_promote_${TS}"

python3 - "$W" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace").splitlines(True)

out=[]
for ln in s:
    if 'X-VSP-RFA-PROMOTE", "v3"' in ln and not ln.lstrip().startswith("#"):
        out.append((" " * (len(ln) - len(ln.lstrip()))) + "# " + ln.lstrip())
    else:
        out.append(ln)

p.write_text("".join(out), encoding="utf-8")
print("[OK] promote header commented (contract still enforced)")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
