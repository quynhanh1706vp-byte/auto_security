#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_healthz_${TS}"
echo "[BACKUP] ${W}.bak_healthz_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_HEALTHZ_WSGI_V1" in s:
    print("[OK] already patched VSP_HEALTHZ_WSGI_V1")
    raise SystemExit(0)

# ensure imports
if "import time" not in s:
    s="import time\n"+s
if "import os" not in s:
    s="import os\n"+s
if "import json" not in s:
    s="import json\n"+s

patch = textwrap.dedent(r'''
# ===== VSP_HEALTHZ_WSGI_V1: /api/vsp/healthz at gateway (never-500) =====
def _vsp_healthz_payload():
    env = os.environ
    return {
        "ok": True,
        "ts": int(time.time()),
        "service": env.get("VSP_UI_SVC","vsp-ui-8910.service"),
        "asset_v": env.get("VSP_ASSET_V"),
        "release_ts": env.get("VSP_RELEASE_TS"),
        "rid_hint": env.get("RID") or env.get("VSP_RID"),
        "ro_mode": "gateway_real_v1",
    }

def _vsp_healthz_resp(start_response):
    j=_vsp_healthz_payload()
    body=(json.dumps(j, ensure_ascii=False)+"\n").encode("utf-8")
    start_response("200 OK", [
        ("Content-Type","application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control","no-store"),
    ])
    return [body]
# ===== end VSP_HEALTHZ_WSGI_V1 =====
''').strip()+"\n"

s = s.rstrip()+"\n\n"+patch+"\n"
# inject into application() dispatch (our wrapper already exists); add near top of try block
# safest: add a small clause right after we compute path
s = re.sub(
    r'(def application\(environ, start_response\):\n\s*try:\n\s*path = environ\.get\("PATH_INFO", ""\) or ""\n)',
    r'\1        if path == "/api/vsp/healthz":\n            return _vsp_healthz_resp(start_response)\n',
    s,
    count=1
)

p.write_text(s, encoding="utf-8")
print("[OK] patched healthz into gateway application()")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== probe healthz =="
curl -sS "$BASE/api/vsp/healthz" | python3 -m json.tool
