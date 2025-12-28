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
cp -f "$WSGI" "${WSGI}.bak_rfa_promote_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfa_promote_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_AFTERREQ_RFA_PROMOTE_FINDINGS_V1"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

# Append at EOF: last-registered after_request will run last (good for overriding XFO)
block = r'''
# ===================== VSP_P0_AFTERREQ_RFA_PROMOTE_FINDINGS_V1 =====================
try:
    from flask import request
    import json as _json

    _APP = globals().get("application") or globals().get("app") or globals().get("_app")
    if _APP is not None and hasattr(_APP, "after_request"):

        @_APP.after_request
        def __vsp_afterreq_rfa_promote_findings_v1(resp):
            try:
                # 1) Promote items/data -> findings for /api/vsp/run_file_allow JSON responses
                if getattr(request, "path", "") == "/api/vsp/run_file_allow":
                    ct = (resp.headers.get("Content-Type") or "")
                    if "application/json" in ct:
                        raw = resp.get_data(as_text=True)
                        obj = _json.loads(raw)

                        if isinstance(obj, dict):
                            # choose candidate list
                            cand = None
                            # top-level items/data
                            for k in ("items", "data"):
                                v = obj.get(k)
                                if isinstance(v, list) and v:
                                    cand = v
                                    break
                            # nested obj["data"].items/data
                            if cand is None:
                                d = obj.get("data")
                                if isinstance(d, dict):
                                    for k in ("items", "data"):
                                        v = d.get(k)
                                        if isinstance(v, list) and v:
                                            cand = v
                                            break

                            # set findings if missing/empty
                            f = obj.get("findings")
                            if (not isinstance(f, list)) or (isinstance(f, list) and not f):
                                if cand is not None:
                                    obj["findings"] = list(cand)
                                    # also ensure nested data.findings exists if data is dict
                                    if isinstance(obj.get("data"), dict):
                                        obj["data"]["findings"] = list(cand)

                                    new_raw = _json.dumps(obj, ensure_ascii=False)
                                    resp.set_data(new_raw.encode("utf-8"))
                                    resp.headers["Content-Length"] = str(len(resp.get_data()))

                # 2) Allow SAMEORIGIN ONLY for raw_v4 (iframe preview), keep others DENY
                if getattr(request, "path", "") == "/api/vsp/run_file_raw_v4":
                    resp.headers["X-Frame-Options"] = "SAMEORIGIN"

            except Exception:
                pass
            return resp

except Exception:
    pass
# =================== /VSP_P0_AFTERREQ_RFA_PROMOTE_FINDINGS_V1 =====================
'''

s2 = s + ("\n" if not s.endswith("\n") else "") + block
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || systemctl restart "$SVC" || true
  echo "[OK] restarted (if service exists)"
fi

echo "== verify run_file_allow findings promoted =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"data_len=",len(j.get("data") or []),"from=",j.get("from"))'

echo "== verify raw_v4 XFO SAMEORIGIN =="
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_file_raw_v4?rid=$RID&path=run_gate_summary.json" | egrep -i 'HTTP/|X-Frame-Options|X-VSP-RAW' || true
