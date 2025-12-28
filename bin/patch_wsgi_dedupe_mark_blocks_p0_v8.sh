#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dedupe_mark_${TS}"
echo "[BACKUP] ${F}.bak_dedupe_mark_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Disable the legacy MARKB block that redefines MARK
# Matches:
#   # VSP_MARK_FIX_P0_V3
#   MARK = "VSP_MARK_P0"
#   MARKB = b"VSP_MARK_P0"
pat = re.compile(r"(?ms)^\s*#\s*VSP_MARK_FIX_P0_V3\s*\n\s*MARK\s*=\s*['\"].*?['\"]\s*\n\s*MARKB\s*=\s*b['\"].*?['\"]\s*\n")
if pat.search(s):
    s = pat.sub("# VSP_MARK_FIX_P0_V3 (disabled by P0_V8: use MARK + MARK_B from P0_V6)\n", s, count=1)

# Also remove any later reassignments of MARK="VSP_MARK_P0" near mid-file (keep only builtins MARK)
s = re.sub(r"(?m)^\s*MARK\s*=\s*['\"]VSP_MARK_P0['\"]\s*$", "# (P0_V8) MARK reassignment removed", s)

p.write_text(s, encoding="utf-8")
print("[OK] deduped legacy MARK blocks")
PY

python3 -m py_compile "$F"
sudo systemctl restart vsp-ui-8910.service

ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening"; exit 3; }
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,20p'
