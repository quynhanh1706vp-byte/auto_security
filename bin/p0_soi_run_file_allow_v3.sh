#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [A] route => function =="
python3 - <<'PY'
import re
s=open("wsgi_vsp_ui_gateway.py","r",encoding="utf-8",errors="replace").read()
m=re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
print("FN="+(m.group(1) if m else "NOT_FOUND"))
PY

echo "== [B] show core lines in handler (rel / ALLOW / not allowed / reports) =="
python3 - <<'PY'
import re
from pathlib import Path
W=Path("wsgi_vsp_ui_gateway.py")
s=W.read_text(encoding="utf-8",errors="replace")
m=re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
fn=m.group(1) if m else None
if not fn:
    print("[ERR] cannot detect function for /api/vsp/run_file_allow"); raise SystemExit(2)
pat=re.compile(r'^\s*def\s+'+re.escape(fn)+r'\s*\(', re.M)
m2=pat.search(s)
if not m2:
    print("[ERR] cannot find def", fn); raise SystemExit(2)
start=m2.start()
tail=s[start:]
lines=tail.splitlines()
# show first ~220 lines but only the interesting ones
for i,ln in enumerate(lines[:220], start=1):
    if ("rel" in ln and "_safe_rel" in ln) or ("ALLOW" in ln) or ("not allowed" in ln) or ("run_gate" in ln) or ("reports/" in ln):
        print(f"{i:04d}: {ln}")
PY
