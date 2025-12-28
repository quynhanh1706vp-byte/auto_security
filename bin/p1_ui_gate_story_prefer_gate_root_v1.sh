#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || JS="static/js/vsp_bundle_commercial_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing vsp_bundle_commercial_v1.js or v2.js"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_gate_root_${TS}"
echo "[BACKUP] ${JS}.bak_gate_root_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

js_path = None
for cand in ["static/js/vsp_bundle_commercial_v2.js","static/js/vsp_bundle_commercial_v1.js"]:
    p=Path(cand)
    if p.exists():
        js_path=p; break
assert js_path

s = js_path.read_text(encoding="utf-8", errors="replace")

# Patch common patterns:
# rid = data.rid_latest || ...
# rid = (data && data.rid_latest) || ...
# We'll insert prefer gate_root/gate before rid_latest.
def repl(m):
    pre = m.group(1)
    return pre + "(data.rid_latest_gate_root||data.rid_latest_gate||data.rid_latest)"

# 1) rid assignment direct
s2, n1 = re.subn(
    r'(\brid\s*=\s*)(?:data\.rid_latest\b)',
    lambda m: m.group(1) + "(data.rid_latest_gate_root||data.rid_latest_gate||data.rid_latest)",
    s
)

# 2) any occurrence of data.rid_latest used as primary selector in a ternary/|| chain
s3, n2 = re.subn(
    r'\bdata\.rid_latest\b(?!_gate_root)(?!_gate)(?!_findings)',
    'data.rid_latest',  # keep others unchanged; we rely on n1 patch
    s2
)

# If n1 == 0, patch alternate pattern where it uses rid_latest from response object named 'd' or 'runs'
# We'll patch the most typical OR chain: (x.rid_latest||"")
if n1 == 0:
    s4, n3 = re.subn(
        r'(\b[a-zA-Z_$][\w$]*\.(?:rid_latest)\b)\s*\|\|\s*',
        lambda m: m.group(0).replace(m.group(1), m.group(1).replace("rid_latest","rid_latest_gate_root") ) + "",
        s3
    )
else:
    n3 = 0
    s4 = s3

js_path.write_text(s4, encoding="utf-8")
print("[OK] patched rid selector. n1=", n1, "n3=", n3, "file=", js_path)
PY

echo "[OK] done. Restart optional if static served with cache-bust; otherwise hard refresh browser."
