#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "def _vsp__read_json_if_exists_v2" "$F" && { echo "[OK] helper already exists"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_add_readjsonv2_${TS}"
echo "[BACKUP] $F.bak_add_readjsonv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

helper = r'''
# === VSP_HELPER_READ_JSON_IF_EXISTS_V2 ===
def _vsp__read_json_if_exists_v2(path):
    """Safe JSON reader used by v2 injectors. Returns dict/list or None."""
    try:
        from pathlib import Path as _Path
        import json as _json
        pp = _Path(path)
        if not pp.is_file():
            return None
        return _json.load(open(pp, "r", encoding="utf-8"))
    except Exception:
        return None
'''

# Insert right before _vsp__inject_degraded_tools_v2 if present, else append at end
m=re.search(r"\n\s*def\s+_vsp__inject_degraded_tools_v2\s*\(", s)
if m:
    s2 = s[:m.start()] + "\n" + helper + "\n" + s[m.start():]
else:
    s2 = s + "\n\n" + helper + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted _vsp__read_json_if_exists_v2")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
