#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head; need curl

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

cp -f "$WSGI" "${WSGI}.bak_topfind_rid_contract_${TS}"
echo "[BACKUP] ${WSGI}.bak_topfind_rid_contract_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_TOPFIND_RID_CONTRACT_WSGI_MW_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
else:
    # inject after Flask app created; try safest insertion near other after_request or near bottom
    inject = r'''
# %s
try:
    import json as _json
    from flask import request as _request
except Exception:
    _json = None
    _request = None

def _vsp__fix_topfind_rid_contract(resp):
    try:
        if _request is None or _json is None:
            return resp
        if not _request.path.startswith("/api/vsp/top_findings_v1"):
            return resp
        ct = resp.headers.get("Content-Type","")
        if "application/json" not in ct:
            return resp
        raw = resp.get_data(as_text=True)
        if not raw:
            return resp
        j = _json.loads(raw)
        ru = j.get("rid_used")
        r  = j.get("rid")
        if ru and r and ru != r:
            j["rid_raw"] = r
            j["rid"] = ru
            out = _json.dumps(j, ensure_ascii=False)
            resp.set_data(out)
            resp.headers["Content-Length"] = str(len(out.encode("utf-8")))
        return resp
    except Exception:
        return resp

try:
    app.after_request(_vsp__fix_topfind_rid_contract)
except Exception:
    pass
# /%s
''' % (MARK, MARK)

    # Heuristic insertion point: after first occurrence of "app =" or "create_app" area
    m = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
    if m:
        # insert a bit after app init block
        ins_at = m.end()
        s2 = s[:ins_at] + "\n" + inject + s[ins_at:]
        s = s2
    else:
        # fallback: append at end
        s = s + "\n\n" + inject

    p.write_text(s, encoding="utf-8")

py_compile.compile("wsgi_vsp_ui_gateway.py", doraise=True)
print("[OK] patched + py_compile ok")
PY

echo "== [RESTART] =="
if [ -n "$SVC" ] && systemctl list-units --full -all | grep -qF "$SVC"; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] service '$SVC' not found in systemd list-units; skip restart"
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [VERIFY] =="
curl -fsS --max-time 3 "$BASE/api/vsp/top_findings_v1?limit=5" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid=",j.get("rid"),"rid_used=",j.get("rid_used"),"rid_raw=",j.get("rid_raw"))'
