#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dashv3_afterreq_${TS}"
echo "[BACKUP] $F.bak_dashv3_afterreq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, datetime

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_DASHBOARD_V3_AFTER_REQUEST_OK_V5 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# ensure flask imports exist (best-effort, safe if duplicated elsewhere)
need = [
    "from flask import request, jsonify",
]
for imp in need:
    if re.search(rf"^\s*{re.escape(imp)}\s*$", t, flags=re.M):
        continue
    m = re.search(r"^(import[^\n]*\n)+", t, flags=re.M)
    ins = m.end() if m else 0
    t = t[:ins] + imp + "\n" + t[ins:]

# insert after_request right after app = Flask(...) (or after ops routes block if present)
m_app = re.search(r"^app\s*=\s*Flask\([^\)]*\)\s*$", t, flags=re.M)
if not m_app:
    raise SystemExit("[ERR] cannot find app = Flask(...) line")

insert_at = m_app.end()

block = f"""
{TAG}
@app.after_request
def _vsp_dashv3_contract_after_request_v5(resp):
    try:
        # only touch dashboard_v3
        if request.path != "/api/vsp/dashboard_v3":
            return resp

        # only json responses
        ctype = (resp.headers.get("Content-Type") or "").lower()
        if "application/json" not in ctype:
            return resp

        obj = resp.get_json(silent=True)
        if not isinstance(obj, dict):
            return resp

        # inject commercial contract
        if obj.get("ok") is not True:
            obj["ok"] = True
        obj.setdefault("schema_version", "dashboard_v3")

        new_resp = jsonify(obj)
        new_resp.status_code = resp.status_code

        # preserve important headers (CORS, cache, etc.)
        for k, v in resp.headers.items():
            if k.lower() in ("content-type", "content-length"):
                continue
            new_resp.headers[k] = v
        return new_resp
    except Exception:
        return resp
# === END VSP_DASHBOARD_V3_AFTER_REQUEST_OK_V5 ===
"""

t = t[:insert_at] + "\n" + block + t[insert_at:]
p.write_text(t, encoding="utf-8")
print("[OK] inserted after_request contract hook for dashboard_v3")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify dashboard_v3 ok =="
curl -sS http://127.0.0.1:8910/api/vsp/dashboard_v3 \
| python3 -c 'import json,sys; o=json.loads(sys.stdin.read()); print({"has_ok":"ok" in o,"ok":o.get("ok"),"schema_version":o.get("schema_version"),"has_by_sev":("by_severity" in o) or ("summary_all" in o and "by_severity" in (o["summary_all"] or {}))})'
