#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_cachedjson_${TS}"
echo "[BACKUP] $F.bak_runv1_cachedjson_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_ALIAS_CACHED_JSON_FIX_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# Replace wrong tuple cache -> dict cache
t2, n = re.subn(
    r"(?m)^(\s*)request\._cached_json\s*=\s*\(\s*payload\s*,\s*payload\s*\)\s*$",
    r"\1request._cached_json = {False: payload, True: payload}  " + TAG,
    t
)

if n == 0:
    # If not found, inject right after the default payload.setdefault(...) lines
    anchor = re.search(
        r"(?ms)# === VSP_RUN_V1_ALIAS_ACCEPT_MINIMAL_V2 ===.*?\n(\s*)payload\.setdefault\('target','/home/test/Data/SECURITY-10-10-v4'\)\s*\n",
        t
    )
    if not anchor:
        raise SystemExit("[ERR] cannot find ACCEPT_MINIMAL block to inject cached_json fix")
    indent = anchor.group(1)
    ins = f"{indent}request._cached_json = {{False: payload, True: payload}}  {TAG}\n"
    t = t[:anchor.end()] + ins + t[anchor.end():]
    print("[OK] injected cached_json dict after defaults")
else:
    t = t2
    print("[OK] replaced tuple cached_json -> dict cached_json, count=", n)

p.write_text(t, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify POST {} to /api/vsp/run_v1 (must NOT 400) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,160p'
