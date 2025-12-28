#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_afterreq_rfa_normv2b_${TS}"
echo "[BACKUP] ${WSGI}.bak_afterreq_rfa_normv2b_${TS}"

python3 - "$WSGI" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_AFTERREQ_RFA_NORMV2B_APPDETECT"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

addon = r'''
# ===================== VSP_P0_AFTERREQ_RFA_NORMV2B_APPDETECT =====================
try:
    # Find the REAL Flask app object (application may be a WSGI callable wrapper).
    _fl = None
    try:
        from flask import Flask
    except Exception:
        Flask = None

    def __vsp_is_flask_app(o):
        if o is None:
            return False
        if Flask is not None:
            try:
                return isinstance(o, Flask)
            except Exception:
                pass
        # fallback heuristic
        return hasattr(o, "after_request") and hasattr(o, "route") and hasattr(o, "view_functions")

    # Preferred names first, but DO NOT stop at 'application' if it's not Flask.
    for _name in ("_app", "app", "flask_app", "vsp_app", "application"):
        o = globals().get(_name)
        if __vsp_is_flask_app(o):
            _fl = o
            break

    # Last resort: scan globals for any Flask-like object
    if _fl is None:
        for _k, _v in list(globals().items()):
            if __vsp_is_flask_app(_v):
                _fl = _v
                break

    if _fl is not None:
        @_fl.after_request
        def __vsp_afterreq_rfa_normv2b(resp):
            try:
                from flask import request
                import json

                if getattr(request, "path", "") != "/api/vsp/run_file_allow":
                    return resp

                ct = (resp.headers.get("Content-Type","") or "").lower()
                if "application/json" not in ct:
                    return resp

                raw = resp.get_data(as_text=True) or ""
                if not raw.strip():
                    return resp

                obj = json.loads(raw)
                if not isinstance(obj, dict):
                    return resp

                # normalize at top-level (your case: obj['data'] is a LIST)
                f = obj.get("findings")
                it = obj.get("items")
                dt = obj.get("data")

                if not f:
                    if isinstance(it, list) and it:
                        obj["findings"] = list(it)
                    elif isinstance(dt, list) and dt:
                        obj["findings"] = list(dt)

                out = json.dumps(obj, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Length"] = str(len(out.encode("utf-8")))
                resp.headers["Cache-Control"] = "no-store"
                resp.headers["X-VSP-RFA-NORM"] = "v2b"
            except Exception:
                pass
            return resp
    else:
        # still keep a marker so we know detection failed (no crash)
        pass
except Exception:
    pass
# ===================== /VSP_P0_AFTERREQ_RFA_NORMV2B_APPDETECT ====================
'''
p.write_text(s + ("\n" if not s.endswith("\n") else "") + addon, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" >/dev/null 2>&1 || systemctl restart "$SVC" || true
  echo "[OK] restarted (if service exists)"
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"

echo "== verify body =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'

echo "== verify header X-VSP-RFA-NORM =="
curl -i -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=1" | head -n 20
