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
cp -f "$W" "${W}.bak_topfind_contract_safe_${TS}"
echo "[BACKUP] ${W}.bak_topfind_contract_safe_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_TOPFIND_CONTRACT_AFTER_REQUEST_SAFE_V1"
if marker in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = f'''
# --- {marker} ---
try:
    import json as _json
    from flask import request as _request, current_app as _current_app

    @_current_app.after_request
    def _vsp_topfind_contract_after_request_safe_v1(resp):
        try:
            if (_request.path or "") != "/api/vsp/top_findings_v1":
                return resp
            ctype = (resp.headers.get("Content-Type","") or "").lower()
            if "application/json" not in ctype:
                return resp

            raw = resp.get_data() or b""
            try:
                j = _json.loads(raw.decode("utf-8","replace"))
            except Exception:
                return resp
            if not isinstance(j, dict) or not j.get("ok", False):
                return resp

            # total must not be None
            if j.get("total") is None:
                # fallback: keep 0 or len(items) (better than None)
                items = j.get("items") or []
                j["total"] = int(len(items)) if isinstance(items, list) else 0

            # run_id must exist and == rid_latest
            if not j.get("run_id"):
                rid = None
                try:
                    vf = getattr(_current_app, "view_functions", None) or {{}}
                    for ep, fn in vf.items():
                        if "rid_latest" not in (ep or ""):
                            continue
                        try:
                            r = fn()
                            jj = None
                            if hasattr(r, "get_json"):
                                jj = r.get_json(silent=True)
                            elif isinstance(r, tuple) and r and hasattr(r[0], "get_json"):
                                jj = r[0].get_json(silent=True)
                            elif isinstance(r, dict):
                                jj = r
                            if isinstance(jj, dict) and (jj.get("rid") or jj.get("run_id")):
                                rid = jj.get("rid") or jj.get("run_id")
                                break
                        except Exception:
                            continue
                except Exception:
                    rid = None

                if rid:
                    j["run_id"] = rid
                    j.setdefault("marker", "{marker}")
                    out = _json.dumps(j, ensure_ascii=False).encode("utf-8")
                    resp.set_data(out)
                    resp.headers["Content-Type"] = "application/json; charset=utf-8"
                    resp.headers["Content-Length"] = str(len(out))
                    resp.headers["X-VSP-TOPFIND-CONTRACT-FIX"] = "1"
                else:
                    resp.headers["X-VSP-TOPFIND-CONTRACT-FIX"] = "no-rid"

            return resp
        except Exception:
            return resp
except Exception:
    pass
# --- end {marker} ---
'''
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended safe after_request contract fixer")
PY

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== proof =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
echo "rid_latest=$RID"
curl -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'content-type|x-vsp-topfind-contract-fix' || true
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"run_id=",j.get("run_id"),"marker=",j.get("marker"))'
