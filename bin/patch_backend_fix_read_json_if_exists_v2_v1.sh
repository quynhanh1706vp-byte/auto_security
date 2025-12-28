#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "def _vsp__read_json_if_exists_v2" "$F" && { echo "[OK] already has _vsp__read_json_if_exists_v2"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_readjsonv2_${TS}"
echo "[BACKUP] $F.bak_fix_readjsonv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

needle = r"def _vsp__inject_degraded_tools_v2\s*\("
m=re.search(needle, s)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp__inject_degraded_tools_v2(")

helper = r'''
def _vsp__read_json_if_exists_v2(path):
    """Best-effort JSON reader. Returns dict/list or None."""
    try:
        from pathlib import Path as _P
        import json as _json
        pp = _P(path)
        if not pp.exists() or pp.stat().st_size <= 0:
            return None
        return _json.load(open(pp, "r", encoding="utf-8"))
    except Exception:
        return None

'''
out = s[:m.start()] + helper + s[m.start():]
p.write_text(out, encoding="utf-8")
print("[OK] inserted _vsp__read_json_if_exists_v2 before _vsp__inject_degraded_tools_v2")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
