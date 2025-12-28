#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_tail_ar_v3_${TS}"
echo "[BACKUP] $F.bak_kics_tail_ar_v3_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG_AR = "VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V2"

# nếu chưa có helpers thì thôi (bạn đã có V2 rồi). Chỉ replace block after_request.
pat = r"(?s)# === " + re.escape(TAG_AR) + r" ===.*?# === END " + re.escape(TAG_AR) + r" ==="
m = re.search(pat, t)
if not m:
    raise SystemExit("[ERR] cannot find after_request tag block to replace (TAG_AR=%s)" % TAG_AR)

new_block = r'''
# === VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V2 ===
def _vsp__inject_kics_tail_to_response(resp):
    try:
        from flask import request as _req
        import json as _json

        path = (_req.path or "")
        if not path.startswith("/api/vsp/run_status_v1/"):
            return resp

        # force allow body read/replace
        try:
            resp.direct_passthrough = False
        except Exception:
            pass

        raw = ""
        try:
            raw = resp.get_data(as_text=True) or ""
        except Exception:
            return resp

        if not raw.strip():
            return resp

        try:
            obj = _json.loads(raw)
        except Exception:
            return resp

        if not isinstance(obj, dict):
            return resp

        if "kics_tail" not in obj:
            ci = obj.get("ci_run_dir") or obj.get("ci_dir") or obj.get("ci_run") or ""
            kt = _vsp_kics_tail_from_ci(ci) if ci else ""
            obj["kics_tail"] = kt if isinstance(kt, str) else str(kt)
        else:
            kt = obj.get("kics_tail")
            if kt is None:
                obj["kics_tail"] = ""
            elif not isinstance(kt, str):
                obj["kics_tail"] = str(kt)

        obj.setdefault("_handler", "after_request_inject:/api/vsp/run_status_v1")

        resp.set_data(_json.dumps(obj, ensure_ascii=False))
        resp.mimetype = "application/json"
        try:
            resp.headers["X-VSP-KICS-TAIL"] = "1"
        except Exception:
            pass
        return resp
    except Exception:
        return resp

try:
    @app.after_request
    def __vsp_after_request_kics_tail_v2(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass

try:
    @bp.after_request
    def __vsp_bp_after_request_kics_tail_v2(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass
# === END VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V2 ===
'''.lstrip("\n")

t2 = t[:m.start()] + new_block + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] replaced after_request block")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] patch v3 hard applied"
