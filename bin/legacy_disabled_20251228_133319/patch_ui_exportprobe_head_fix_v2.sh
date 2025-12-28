#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_headfix_v2_${TS}"
echo "[BACKUP] $F.bak_headfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

# Replace method/url extraction inside our injected wrapper
old = r"""const method = (init && init.method) ? String(init.method).toUpperCase() : "GET";
          const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");"""

new = r"""const method = (init && init.method)
            ? String(init.method).toUpperCase()
            : (input && input.method ? String(input.method).toUpperCase() : "GET");
          const url = (typeof input === "string")
            ? input
            : (input && input.url ? String(input.url) : "");"""

if old in s:
    s2 = s.replace(old, new, 1)
    p.write_text(s2, encoding="utf-8")
    print("[OK] updated fetch wrapper method/url extraction (v2)")
else:
    # fallback regex if spacing differs
    s2 = re.sub(
        r"const method\s*=\s*\(init\s*&&\s*init\.method\)\s*\?\s*String\(init\.method\)\.toUpperCase\(\)\s*:\s*\"GET\";\s*[\r\n]+\s*const url\s*=\s*\(typeof input === \"string\"\)\s*\?\s*input\s*:\s*\(input\s*&&\s*input\.url\s*\?\s*input\.url\s*:\s*\"\"\);\s*",
        new + "\n",
        s,
        count=1
    )
    if s2 != s:
        p.write_text(s2, encoding="utf-8")
        print("[OK] updated via regex (v2)")
    else:
        print("[WARN] did not find target block; patch may already be v2 or code differs")

PY

echo "[DONE] v2 patch applied: $F"
