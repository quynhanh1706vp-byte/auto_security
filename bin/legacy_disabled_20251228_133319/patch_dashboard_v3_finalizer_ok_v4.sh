#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dashv3_finalizer_${TS}"
echo "[BACKUP] $F.bak_dashv3_finalizer_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_DASHBOARD_V3_FINALIZER_OK_V4 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# find the normalizer hook that already checks path == "/api/vsp/dashboard_v3"
pat = re.compile(r'(\s*)if\s+path\s*==\s*["\']/api/vsp/dashboard_v3["\']\s+and\s+isinstance\(data,\s*dict\)\s*:\s*\n', re.M)
m = pat.search(t)
if not m:
    raise SystemExit("[ERR] cannot find normalizer: if path == '/api/vsp/dashboard_v3' and isinstance(data, dict):")

indent = m.group(1) + "    "  # inside if block
ins = (
    f"{indent}{TAG}\n"
    f"{indent}# commercial contract: always expose ok/schema_version for dashboard_v3\n"
    f"{indent}data.setdefault('ok', True)\n"
    f"{indent}data.setdefault('schema_version', 'dashboard_v3')\n"
    f"{indent}# === END VSP_DASHBOARD_V3_FINALIZER_OK_V4 ===\n"
)

# insert right after the if-line
pos = m.end()
t2 = t[:pos] + ins + t[pos:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted dashboard_v3 finalizer ok/schema_version")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify dashboard_v3 ok =="
curl -sS http://127.0.0.1:8910/api/vsp/dashboard_v3 \
| python3 -c 'import json,sys; o=json.loads(sys.stdin.read()); print({"has_ok":"ok" in o,"ok":o.get("ok"),"schema_version":o.get("schema_version"),"has_by_sev":("by_severity" in o) or ("summary_all" in o and "by_severity" in (o["summary_all"] or {}))})'
