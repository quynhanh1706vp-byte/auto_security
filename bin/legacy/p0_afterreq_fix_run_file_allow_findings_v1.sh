#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_afterreq_rfa_findings_${TS}"
echo "[BACKUP] ${WSGI}.bak_afterreq_rfa_findings_${TS}"

python3 - "$WSGI" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_AFTERREQ_RFA_FINDINGS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

snippet = r'''

# --- VSP_P0_AFTERREQ_RFA_FINDINGS_V1 ---
try:
    import json
    try:
        from flask import request
    except Exception:
        request = None

    if "application" in globals() and hasattr(globals()["application"], "after_request"):

        @globals()["application"].after_request
        def __vsp_afterreq_rfa_findings_v1(resp):
            try:
                if request is None:
                    return resp
                if request.path != "/api/vsp/run_file_allow":
                    return resp
                ct = (resp.headers.get("Content-Type") or "").lower()
                if "application/json" not in ct:
                    return resp

                obj = None
                try:
                    obj = resp.get_json(silent=True)
                except Exception:
                    obj = None
                if not isinstance(obj, dict):
                    return resp

                f = obj.get("findings")
                if isinstance(f, list) and len(f) > 0:
                    return resp

                it = obj.get("items")
                dt = obj.get("data")
                if isinstance(it, list) and len(it) > 0:
                    obj["findings"] = list(it)
                elif isinstance(dt, list) and len(dt) > 0:
                    obj["findings"] = list(dt)
                else:
                    return resp

                resp.set_data(json.dumps(obj, ensure_ascii=False))
                resp.headers["Content-Type"] = "application/json"
                resp.headers.pop("Content-Length", None)
            except Exception:
                return resp
            return resp

        print("[VSP_AFTERREQ] mounted findings-normalizer for /api/vsp/run_file_allow")
except Exception:
    pass
# --- /VSP_P0_AFTERREQ_RFA_FINDINGS_V1 ---

'''
p.write_text(s + snippet, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"

echo "== verify run_file_allow findings normalized =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"data_len=",len(j.get("data") or []),"from=",j.get("from"))'
