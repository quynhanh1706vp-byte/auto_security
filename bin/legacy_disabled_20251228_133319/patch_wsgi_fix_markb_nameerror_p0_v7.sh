#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_markb_${TS}"
echo "[BACKUP] ${F}.bak_fix_markb_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Fix the buggy self-referential MARK_B assignment
bad = r"MARK_B\s*=\s*\(\s*MARK_B\s*if\s*isinstance\s*\(\s*MARK\s*,\s*str\s*\)\s*else\s*str\s*\(\s*MARK\s*\)\.encode\s*\(\s*\)\s*\)"
good = "MARK_B = (MARK.encode() if isinstance(MARK, str) else str(MARK).encode())"

if re.search(bad, s):
    s = re.sub(bad, good, s, count=1)
else:
    # fallback: if there's any line starting with MARK_B = (MARK_B ...
    s = re.sub(r"^(\s*)MARK_B\s*=\s*\(\s*MARK_B\s*if\s*isinstance\(\s*MARK\s*,\s*str\s*\)\s*else\s*str\(\s*MARK\s*\)\.encode\(\s*\)\s*\)\s*$",
               r"\1" + good, s, flags=re.M, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched MARK_B assignment")
PY

echo "== py_compile =="
python3 -m py_compile "$F"

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl reset-failed vsp-ui-8910.service || true
sudo systemctl restart vsp-ui-8910.service

echo "== verify listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening on 8910"; exit 3; }

echo "== verify curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,20p'
