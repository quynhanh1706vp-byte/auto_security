#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p511_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P510_CSP_REPORTONLY_COOP_CORP_V1" not in s:
    raise SystemExit("[ERR] P510 marker missing")

# swap header name: Report-Only -> Enforce
s2 = s.replace("Content-Security-Policy-Report-Only", "Content-Security-Policy")

# marker to track
if "VSP_P511_CSP_ENFORCE_V1" not in s2:
    s2 += "\n# VSP_P511_CSP_ENFORCE_V1\n"

p.write_text(s2, encoding="utf-8")
print("[OK] CSP enforce enabled")
PY

python3 -m py_compile "$T" && echo "[OK] py_compile $T"
sudo systemctl restart vsp-ui-8910.service
echo "[OK] restarted"
