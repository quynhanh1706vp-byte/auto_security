#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

grep -q "VSP_RID_STATE_V1" "$T" && { echo "[OK] template already has RID state"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_ridstate_${TS}"
echo "[BACKUP] $T.bak_ridstate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) add RID label near export buttons area (best effort)
if "id=\"vsp-rid-label\"" not in s:
    # put after Export buttons if found
    s2=re.sub(r'(id="export-pdf"[^>]*>[^<]*</button>\s*)',
              r'\1<span id="vsp-rid-label" style="margin-left:10px;opacity:.85;font-size:12px">RID: (none)</span>',
              s, count=1, flags=re.I|re.S)
    if s2==s:
        # fallback: inject at top body
        s2=s.replace("<body", "<body")\
             .replace(">", ">\n<div style='position:sticky;top:0;z-index:5'>"
                          "<span id='vsp-rid-label' style='margin-left:12px;opacity:.85;font-size:12px'>RID: (none)</span>"
                          "</div>\n", 1)
    s=s2

# 2) inject script tag before closing body
inject = "\n<!-- VSP_RID_STATE_V1 -->\n<script src=\"/static/js/vsp_rid_state_v1.js?v=1\"></script>\n"
if "vsp_rid_state_v1.js" not in s:
    s=s.replace("</body>", inject + "</body>")

p.write_text(s, encoding="utf-8")
print("[OK] injected RID label + script")
PY
