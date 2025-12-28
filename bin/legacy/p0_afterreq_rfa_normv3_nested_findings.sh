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
cp -f "$WSGI" "${WSGI}.bak_rfa_normv3_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfa_normv3_${TS}"

python3 - "$WSGI" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_AFTERREQ_RFA_NORMV3_NESTED"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

addon = r'''
# ==================== VSP_P0_AFTERREQ_RFA_NORMV3_NESTED (items/data -> findings) ====================
def __vsp__rfa_norm_obj_v3(_r):
    try:
        # normalize dict-like
        if isinstance(_r, dict):
            # 1) normalize nested "data" dict if present
            _d = _r.get("data")
            if isinstance(_d, dict):
                _f = _d.get("findings")
                if not _f:
                    _it = _d.get("items")
                    _dt = _d.get("data")
                    if isinstance(_it, list) and len(_it) > 0:
                        _d["findings"] = list(_it)
                    elif isinstance(_dt, list) and len(_dt) > 0:
                        _d["findings"] = list(_dt)

            # 2) normalize top-level too (some code reads top-level keys)
            _f2 = _r.get("findings")
            if not _f2:
                _it2 = _r.get("items")
                _dt2 = _r.get("data")
                if isinstance(_it2, list) and len(_it2) > 0:
                    _r["findings"] = list(_it2)
                elif isinstance(_dt2, list) and len(_dt2) > 0:
                    _r["findings"] = list(_dt2)
                elif isinstance(_d, dict) and isinstance(_d.get("findings"), list) and len(_d.get("findings")) > 0:
                    _r["findings"] = list(_d["findings"])
    except Exception:
        pass
    return _r

def __vsp__install_afterreq_rfa_normv3_nested():
    try:
        import json
        # best-effort detect flask app object
        _app = None
        for k in ("application","app","_app"):
            v = globals().get(k)
            if v is not None and hasattr(v, "after_request"):
                _app = v
                break
        if _app is None:
            return False

        def _hook(resp):
            try:
                # only for run_file_allow JSON
                try:
                    from flask import request
                except Exception:
                    request = None
                if request is None:
                    return resp
                if request.path != "/api/vsp/run_file_allow":
                    return resp
                ct = (resp.headers.get("Content-Type","") or "")
                if "application/json" not in ct:
                    return resp

                raw = resp.get_data(as_text=True) or ""
                if not raw or raw[:1] not in "{[":
                    return resp
                obj = json.loads(raw)
                obj = __vsp__rfa_norm_obj_v3(obj)
                out = json.dumps(obj, ensure_ascii=False)
                resp.set_data(out.encode("utf-8"))
                resp.headers["Content-Length"] = str(len(resp.get_data()))
                resp.headers["X-VSP-RFA-NORM"] = "v3_nested"
            except Exception:
                pass
            return resp

        # register
        _app.after_request(_hook)
        return True
    except Exception:
        return False

# marker
VSP_P0_AFTERREQ_RFA_NORMV3_NESTED = True
__vsp__install_afterreq_rfa_normv3_nested()
# ==================== /VSP_P0_AFTERREQ_RFA_NORMV3_NESTED ====================
'''
p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  echo "[OK] restarted (if service exists)"
fi

echo "== verify findings normalized =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"data_len=",len(j.get("data") or []),"hdr_from=",j.get("from"))'
curl -i -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=1" | head -n 12
