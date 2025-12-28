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
cp -f "$WSGI" "${WSGI}.bak_afterreq_rfa_findings_v1b_${TS}"
echo "[BACKUP] ${WSGI}.bak_afterreq_rfa_findings_v1b_${TS}"

python3 - "$WSGI" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_AFTERREQ_RFA_FINDINGS_V1B_AUTODETECT"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

snippet = r'''

# --- VSP_P0_AFTERREQ_RFA_FINDINGS_V1B_AUTODETECT ---
try:
    import json
    from flask import request

    def __vsp_afterreq_rfa_findings_v1b(resp):
        """
        Normalize /api/vsp/run_file_allow JSON so UI can always read .findings.
        If findings is empty but items/data exists => copy into findings.
        Also stamp header so we can confirm hook executed.
        """
        try:
            # stamp "hook ran" header always for this endpoint (helps debug)
            if getattr(request, "path", "") == "/api/vsp/run_file_allow":
                try:
                    resp.headers["X-VSP-AFTERREQ-RFA"] = "v1b"
                except Exception:
                    pass
            else:
                return resp

            # get text
            body = None
            try:
                body = resp.get_data(as_text=True)
            except Exception:
                body = None
            if not body:
                return resp

            # parse json robustly (even if Content-Type not json)
            obj = None
            try:
                obj = json.loads(body)
            except Exception:
                return resp
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

            # write back
            resp.set_data(json.dumps(obj, ensure_ascii=False))
            try:
                resp.headers["Content-Type"] = "application/json"
            except Exception:
                pass
            resp.headers.pop("Content-Length", None)
        except Exception:
            return resp
        return resp

    # attach to any Flask-like app objects in module globals
    _cnt = 0
    for _name, _obj in list(globals().items()):
        try:
            if hasattr(_obj, "after_request") and hasattr(_obj, "route") and hasattr(_obj, "add_url_rule"):
                _obj.after_request(__vsp_afterreq_rfa_findings_v1b)
                _cnt += 1
        except Exception:
            pass

    print(f"[VSP_AFTERREQ] attached RFA findings-normalizer to {_cnt} app object(s)")
except Exception:
    pass
# --- /VSP_P0_AFTERREQ_RFA_FINDINGS_V1B_AUTODETECT ---

'''
p.write_text(s + snippet, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"

echo "== verify header + findings normalized =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"

# show header marker
curl -i -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" | head -n 25

# show lengths
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"data_len=",len(j.get("data") or []),"from=",j.get("from"))'
