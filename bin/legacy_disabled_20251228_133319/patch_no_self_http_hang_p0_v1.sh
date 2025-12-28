#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_no_selfhttp_${TS}" && echo "[BACKUP] $F.bak_no_selfhttp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Replace whole function def _vsp_http_get_json_local(...) with a safe version
pat = r"def _vsp_http_get_json_local\s*\([^)]*\):\n(?:[ \t].*\n)+"
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_http_get_json_local(...) to patch")

new_fn = """def _vsp_http_get_json_local(path, timeout_sec=1.8):
    \\"""P0 commercial: never hang worker by self-calling local HTTP. Fail-soft.\\""" 
    import json, urllib.request
    url = "http://127.0.0.1:8910" + str(path)
    try:
        req = urllib.request.Request(url, headers={"Accept":"application/json"})
        with urllib.request.urlopen(req, timeout=float(timeout_sec)) as resp:
            raw = resp.read().decode("utf-8", "ignore")
            return json.loads(raw) if raw else {}
    except Exception as e:
        # degraded-safe payload (UI should treat as degraded, not crash)
        try:
            return {"_degraded": True, "_error": str(e), "_path": str(path), "_url": url}
        except Exception:
            return {"_degraded": True, "_path": str(path)}
"""

s2 = s[:m.start()] + new_fn + "\n" + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched _vsp_http_get_json_local (fail-soft)")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
