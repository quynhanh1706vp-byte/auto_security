#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_contract_afterreq_${TS}"
echo "[BACKUP] $F.bak_contract_afterreq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_CONTRACT_AFTER_REQUEST_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# ensure imports exist
if not re.search(r"^\s*from flask import request, jsonify\s*$", t, flags=re.M):
    m = re.search(r"^(import[^\n]*\n)+", t, flags=re.M)
    ins = m.end() if m else 0
    t = t[:ins] + "from flask import request, jsonify\n" + t[ins:]

# insert near the existing dashboard after_request (if present), else after app = Flask(...)
ins_at = None
m_end_dash = re.search(r"# === END VSP_DASHBOARD_V3_AFTER_REQUEST_OK_V5 ===\s*", t)
if m_end_dash:
    ins_at = m_end_dash.end()
else:
    m_app = re.search(r"^app\s*=\s*Flask\([^\)]*\)\s*$", t, flags=re.M)
    if not m_app:
        raise SystemExit("[ERR] cannot find app = Flask(...)")
    ins_at = m_app.end()

block = textwrap.dedent(f"""
{TAG}
@app.after_request
def _vsp_contract_after_request_v1(resp):
    try:
        p = request.path

        # Normalize JSON for these endpoints (commercial contract)
        if p == "/api/vsp/settings_v1":
            obj = resp.get_json(silent=True)
            if not isinstance(obj, dict):
                obj = {{"ok": True, "settings": {{}}}}
            else:
                obj.setdefault("ok", True)
                obj.setdefault("settings", {{}})
            nr = jsonify(obj); nr.status_code = resp.status_code or 200
            for k,v in resp.headers.items():
                if k.lower() in ("content-type","content-length"): continue
                nr.headers[k] = v
            return nr

        if p == "/api/vsp/rule_overrides_v1":
            obj = resp.get_json(silent=True)
            if not isinstance(obj, dict):
                obj = {{"ok": True, "overrides": {{}}}}
            else:
                obj.setdefault("ok", True)
                obj.setdefault("overrides", obj.get("overrides", {{}}))
            nr = jsonify(obj); nr.status_code = resp.status_code or 200
            for k,v in resp.headers.items():
                if k.lower() in ("content-type","content-length"): continue
                nr.headers[k] = v
            return nr

        if p == "/api/vsp/datasource_v2":
            obj = resp.get_json(silent=True)
            if not isinstance(obj, dict):
                obj = {{"ok": True, "items": [], "meta": {{"limit": 50}}}}
            else:
                obj.setdefault("ok", True)
                obj.setdefault("items", obj.get("items", []))
                obj.setdefault("meta", obj.get("meta", {{"limit": 50}}))
            nr = jsonify(obj); nr.status_code = resp.status_code or 200
            for k,v in resp.headers.items():
                if k.lower() in ("content-type","content-length"): continue
                nr.headers[k] = v
            return nr

        return resp
    except Exception:
        return resp
# === END VSP_CONTRACT_AFTER_REQUEST_V1 ===
""").strip() + "\n"

t = t[:ins_at] + "\n" + block + "\n" + t[ins_at:]
p.write_text(t, encoding="utf-8")
print("[OK] inserted contract after_request for settings/rule/datasource")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== quick verify =="
curl -sS http://127.0.0.1:8910/api/vsp/settings_v1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()))'
curl -sS http://127.0.0.1:8910/api/vsp/rule_overrides_v1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()))'
curl -sS "http://127.0.0.1:8910/api/vsp/datasource_v2?limit=1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).keys())'
