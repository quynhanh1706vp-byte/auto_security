#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_embed_rid_${TS}" && echo "[BACKUP] $T.bak_embed_rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

t=Path("templates/vsp_4tabs_commercial_v1.html")
s=t.read_text(encoding="utf-8", errors="ignore")

marker="VSP_TPL_EMBED_RID_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# Add a hidden RID marker in body top (works even with router)
ins = r'''
<!-- === VSP_TPL_EMBED_RID_P1_V1 === -->
<div id="vsp-rid-embed" data-rid="{{ rid|default('') }}" style="display:none"></div>
'''

# Insert right after <body ...>
m = re.search(r'(?is)<body[^>]*>', s)
if not m:
    raise SystemExit("[ERR] cannot find <body> in template")

pos = m.end()
s = s[:pos] + "\n" + ins + "\n" + s[pos:]

t.write_text(s, encoding="utf-8")
print("[OK] injected", marker)
PY
echo "[OK] patched template embed rid"
