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
cp -f "$WSGI" "${WSGI}.bak_static_rfa_hotfix_${TS}"
echo "[BACKUP] ${WSGI}.bak_static_rfa_hotfix_${TS}"

python3 - "$WSGI" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

M1="VSP_P0_STATIC_MIME_RESCUE_V1"
M2="VSP_P0_RUN_FILE_ALLOW_PROMOTE_FINDINGS_V2"

add=[]
if M1 not in s:
    add.append(r'''
# ===================== VSP_P0_STATIC_MIME_RESCUE_V1 =====================
try:
    from flask import request
    from pathlib import Path as _Path

    _APP = globals().get("application") or globals().get("app") or globals().get("_app")
    if _APP is not None and hasattr(_APP, "after_request"):

        @_APP.after_request
        def __vsp_static_mime_rescue_v1(resp):
            try:
                _p = getattr(request, "path", "") or ""
                if _p.startswith("/static/") and (_p.endswith(".js") or _p.endswith(".css")):
                    ct = (resp.headers.get("Content-Type") or "")
                    # when mis-routed, gateway often returns JSON w/ application/json
                    if ("application/json" in ct) or (ct.strip() == ""):
                        rel = _p.lstrip("/")
                        fp = _Path(__file__).resolve().parent / rel
                        if fp.is_file():
                            data = fp.read_bytes()
                            resp.set_data(data)
                            resp.status_code = 200
                            if _p.endswith(".js"):
                                resp.headers["Content-Type"] = "application/javascript; charset=utf-8"
                            else:
                                resp.headers["Content-Type"] = "text/css; charset=utf-8"
                            resp.headers["Content-Length"] = str(len(data))
                            resp.headers["X-VSP-STATIC-RESCUE"] = "v1"
            except Exception:
                pass
            return resp
except Exception:
    pass
# =================== /VSP_P0_STATIC_MIME_RESCUE_V1 =====================
''')

if M2 not in s:
    add.append(r'''
# ===================== VSP_P0_RUN_FILE_ALLOW_PROMOTE_FINDINGS_V2 =====================
try:
    from flask import request
    import json as _json

    _APP = globals().get("application") or globals().get("app") or globals().get("_app")
    if _APP is not None and hasattr(_APP, "after_request"):

        @_APP.after_request
        def __vsp_rfa_promote_findings_v2(resp):
            try:
                if getattr(request, "path", "") == "/api/vsp/run_file_allow":
                    # allow reading body even if response was streamed
                    if hasattr(resp, "direct_passthrough") and resp.direct_passthrough:
                        resp.direct_passthrough = False

                    ct = (resp.headers.get("Content-Type") or "")
                    if "application/json" in ct:
                        raw = resp.get_data(as_text=True)
                        obj = _json.loads(raw) if raw else None
                        if isinstance(obj, dict):
                            cand = None
                            # top-level items/data
                            for k in ("items", "data"):
                                v = obj.get(k)
                                if isinstance(v, list) and v:
                                    cand = v
                                    break
                            # nested data.items/data
                            if cand is None and isinstance(obj.get("data"), dict):
                                d=obj["data"]
                                for k in ("items", "data"):
                                    v = d.get(k)
                                    if isinstance(v, list) and v:
                                        cand = v
                                        break

                            f = obj.get("findings")
                            if (not isinstance(f, list)) or (isinstance(f, list) and not f):
                                if cand is not None:
                                    obj["findings"] = list(cand)
                                    if isinstance(obj.get("data"), dict):
                                        obj["data"]["findings"] = list(cand)
                                    new_raw = _json.dumps(obj, ensure_ascii=False)
                                    resp.set_data(new_raw.encode("utf-8"))
                                    resp.headers["Content-Length"] = str(len(resp.get_data()))
                                    resp.headers["X-VSP-RFA-PROMOTE"] = "v2"
            except Exception:
                pass
            return resp
except Exception:
    pass
# =================== /VSP_P0_RUN_FILE_ALLOW_PROMOTE_FINDINGS_V2 =====================
''')

if add:
    s2 = s + ("\n" if not s.endswith("\n") else "") + "\n".join(add)
    p.write_text(s2, encoding="utf-8")
    print("[OK] appended:", ", ".join([m for m in (M1,M2) if m in s2]))
else:
    print("[OK] markers already exist; nothing to do")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || systemctl restart "$SVC" || true
  echo "[OK] restarted (if service exists)"
fi

echo "== verify: JS served as javascript (not json) =="
curl -sS -D- -o /dev/null "$BASE/static/js/vsp_data_source_lazy_v1.js" | egrep -i 'HTTP/|Content-Type|X-VSP-STATIC-RESCUE' || true

echo "== verify: run_file_allow findings promoted =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"data_len=",len(j.get("data") or []),"hdr_promote=",("X-VSP-RFA-PROMOTE" in j))'
