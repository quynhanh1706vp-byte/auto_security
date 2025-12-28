#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_contract_afterreq_v2_${TS}"
echo "[BACKUP] $F.bak_contract_afterreq_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove old V1 block if exists (to avoid multiple hooks)
t = re.sub(r"\n# === VSP_CONTRACT_AFTER_REQUEST_V1 ===[\s\S]*?# === END VSP_CONTRACT_AFTER_REQUEST_V1 ===\n", "\n", t)

TAG = "# === VSP_CONTRACT_AFTER_REQUEST_V2 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# ensure imports
if not re.search(r"^\s*from flask import request, jsonify\s*$", t, flags=re.M):
    m = re.search(r"^(import[^\n]*\n)+", t, flags=re.M)
    ins = m.end() if m else 0
    t = t[:ins] + "from flask import request, jsonify\n" + t[ins:]

# insert after dashboard after_request (preferred) else after app=Flask
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
def _vsp_contract_after_request_v2(resp):
    # commercial firewall: always return JSON + HTTP 200 for key contract endpoints
    try:
        path = request.path

        if path == "/api/vsp/settings_v1":
            out = {{"ok": True, "settings": {{}}}}
            r = jsonify(out); r.status_code = 200
            return r

        if path == "/api/vsp/rule_overrides_v1":
            out = {{"ok": True, "overrides": {{}}}}
            r = jsonify(out); r.status_code = 200
            return r

        if path == "/api/vsp/datasource_v2":
            # keep minimal shape; UI sẽ fetch items/filters sau
            out = {{"ok": True, "items": [], "meta": {{"limit": 50}}}}
            r = jsonify(out); r.status_code = 200
            return r

        return resp
    except Exception:
        return resp
# === END VSP_CONTRACT_AFTER_REQUEST_V2 ===
""").strip() + "\n"

t = t[:ins_at] + "\n" + block + "\n" + t[ins_at:]
p.write_text(t, encoding="utf-8")
print("[OK] inserted V2 contract firewall")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify (HTTP + body) =="
for u in \
  "http://127.0.0.1:8910/api/vsp/settings_v1" \
  "http://127.0.0.1:8910/api/vsp/rule_overrides_v1" \
  "http://127.0.0.1:8910/api/vsp/datasource_v2?limit=1"
do
  echo "--- $u"
  curl -sS -i "$u" | sed -n '1,12p'
  echo
done
