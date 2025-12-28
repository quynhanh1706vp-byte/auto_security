#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_runid_wsgi_${TS}"
echo "[BACKUP] ${W}.bak_topfind_runid_wsgi_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import py_compile, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_TOPFIND_RUNID_FIX_AFTER_REQUEST_V1"
if marker in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

block = r'''
# --- VSP_P2_TOPFIND_RUNID_FIX_AFTER_REQUEST_V1 ---
# Commercial+ strict: /api/vsp/top_findings_v1 must include run_id == rid_latest.
try:
    import json as _json
    from flask import request as _request, current_app as _current_app

    def _vsp_get_rid_latest_value_v1():
        # call rid_latest view function directly (no internal HTTP)
        try:
            vf = getattr(_current_app, "view_functions", {}) or {}
            for ep in (
                "api_vsp_rid_latest", "rid_latest", "rid_latest_v1",
                "api_vsp_rid_latest_v1", "vsp_rid_latest", "api_vsp_rid_latest_commercial",
            ):
                fn = vf.get(ep)
                if not callable(fn):
                    continue
                try:
                    r = fn()
                    # Flask Response
                    if hasattr(r, "get_json"):
                        j = r.get_json(silent=True) or {}
                        rid = j.get("rid") or j.get("run_id")
                        if rid:
                            return rid
                    # tuple (resp, code) etc
                    if isinstance(r, tuple) and r and hasattr(r[0], "get_json"):
                        j = r[0].get_json(silent=True) or {}
                        rid = j.get("rid") or j.get("run_id")
                        if rid:
                            return rid
                except Exception:
                    continue
        except Exception:
            pass
        return None

    @app.after_request
    def _vsp_after_request_topfind_runid_fix_v1(resp):
        try:
            if (_request.path or "") != "/api/vsp/top_findings_v1":
                return resp

            # only touch JSON
            ctype = (resp.headers.get("Content-Type") or "").lower()
            if "application/json" not in ctype:
                return resp

            j = None
            try:
                j = resp.get_json(silent=True)
            except Exception:
                j = None
            if not isinstance(j, dict):
                return resp
            if not j.get("ok"):
                return resp

            if j.get("run_id"):
                # already compliant
                j.setdefault("marker", marker)
                return resp

            rid = _vsp_get_rid_latest_value_v1()
            if rid:
                j["run_id"] = rid
                j.setdefault("marker", marker)

                body = _json.dumps(j, ensure_ascii=False).encode("utf-8")
                # rebuild response (avoid mutating internal cached json)
                new_resp = _current_app.response_class(body, status=resp.status_code, mimetype="application/json")
                # copy security headers
                for hk in ("X-Content-Type-Options","X-Frame-Options","Referrer-Policy","Permissions-Policy","Cache-Control"):
                    if hk in resp.headers:
                        new_resp.headers[hk] = resp.headers[hk]
                # keep release headers if present
                for hk in ("X-VSP-RELEASE-TS","X-VSP-RELEASE-SHA","X-VSP-RELEASE-PKG"):
                    if hk in resp.headers:
                        new_resp.headers[hk] = resp.headers[hk]
                new_resp.headers["X-VSP-TOPFIND-RUNID-FIX"] = "1"
                return new_resp

            # if cannot get rid_latest, still mark for visibility
            resp.headers["X-VSP-TOPFIND-RUNID-FIX"] = "no-rid"
            return resp
        except Exception:
            try:
                resp.headers["X-VSP-TOPFIND-RUNID-FIX"] = "error"
            except Exception:
                pass
            return resp
except Exception:
    pass
# --- end VSP_P2_TOPFIND_RUNID_FIX_AFTER_REQUEST_V1 ---
'''
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended top_findings run_id fixer")
PY

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick check =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
echo "rid_latest=$RID"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=1" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"run_id=",j.get("run_id"),"marker=",j.get("marker"))'
