#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_no_selfhttp_v2_${TS}" && echo "[BACKUP] $F.bak_no_selfhttp_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")
needle = "def _vsp_http_get_json_local"
i = s.find(needle)
if i < 0:
    raise SystemExit("[ERR] cannot find def _vsp_http_get_json_local in vsp_demo_app.py")

# find function start at line boundary
start = s.rfind("\n", 0, i) + 1

# find next top-level def after start (skip the current line)
j = s.find("\ndef ", i + 1)
if j < 0:
    end = len(s)
else:
    end = j + 1  # keep leading newline for next def

new_fn = (
"def _vsp_http_get_json_local(path, timeout_sec=1.8):\n"
"    # P0 commercial: never hang worker by self-calling local HTTP. Fail-soft.\n"
"    import json, urllib.request\n"
"    url = 'http://127.0.0.1:8910' + str(path)\n"
"    try:\n"
"        req = urllib.request.Request(url, headers={'Accept': 'application/json'})\n"
"        with urllib.request.urlopen(req, timeout=float(timeout_sec)) as resp:\n"
"            raw = resp.read().decode('utf-8', 'ignore')\n"
"            return json.loads(raw) if raw else {}\n"
"    except Exception as e:\n"
"        return {'_degraded': True, '_error': str(e), '_path': str(path), '_url': url}\n"
"\n"
)

s2 = s[:start] + new_fn + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched _vsp_http_get_json_local (v2 fail-soft)")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
