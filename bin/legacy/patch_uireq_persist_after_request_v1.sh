#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_uireq_persist_${TS}"
echo "[BACKUP] $F.bak_uireq_persist_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_UIREQ_PERSIST_AFTER_REQUEST_V1 ==="
if TAG in txt:
    print("[OK] already patched")
    raise SystemExit(0)

BLOCK = r'''
# === VSP_UIREQ_PERSIST_AFTER_REQUEST_V1 ===
import json, os, sys, time
from pathlib import Path as _Path
try:
    from flask import request as _vsp_request
except Exception:
    _vsp_request = None

def _vsp_persist_uireq_state_v1(payload: dict):
    try:
        if not isinstance(payload, dict):
            return
        rid = payload.get("request_id") or payload.get("req_id") or payload.get("rid") or payload.get("run_id")
        if not rid or not isinstance(rid, str):
            return

        base = _Path(__file__).resolve().parent / "out_ci"
        # giữ tương thích: vừa ui_req_state (cũ) vừa uireq_v1 (mới/chuẩn)
        for sub in ("ui_req_state", "uireq_v1"):
            d = base / sub
            d.mkdir(parents=True, exist_ok=True)
            fp = d / f"{rid}.json"
            tmp = d / f"{rid}.json.tmp"

            payload2 = dict(payload)
            payload2["_persisted_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            payload2["_persisted_by"] = "VSP_UIREQ_PERSIST_AFTER_REQUEST_V1"
            tmp.write_text(json.dumps(payload2, ensure_ascii=False, indent=2), encoding="utf-8")
            os.replace(tmp, fp)
    except Exception as e:
        try:
            print(f"[VSP_UIREQ_PERSIST][WARN] {e}", file=sys.stderr)
        except Exception:
            pass

# lưu state cho run_v1 + run_status_v1 mà không đụng logic endpoint
try:
    @app.after_request
    def _vsp_uireq_after_request_v1(resp):
        try:
            if _vsp_request is None:
                return resp
            path = (_vsp_request.path or "")
            if not (path == "/api/vsp/run_v1" or path.startswith("/api/vsp/run_status_v1/")):
                return resp
            if getattr(resp, "status_code", 0) != 200:
                return resp
            mt = getattr(resp, "mimetype", "") or ""
            if "json" not in mt:
                return resp
            data = resp.get_json(silent=True)
            if isinstance(data, dict):
                _vsp_persist_uireq_state_v1(data)
        except Exception:
            pass
        return resp
except Exception as _e:
    # đừng làm app crash nếu biến app khác tên; log nhẹ
    try:
        print(f"[VSP_UIREQ_PERSIST][WARN] cannot attach after_request: {_e}", file=sys.stderr)
    except Exception:
        pass
# === END VSP_UIREQ_PERSIST_AFTER_REQUEST_V1 ===
'''

m = re.search(r'^\s*app\s*=\s*Flask\([^\n]*\)\s*$', txt, flags=re.M)
if not m:
    # fallback: append cuối file (nhưng decorator cần app; đa số vẫn có app)
    txt2 = txt + "\n\n" + BLOCK + "\n"
    p.write_text(txt2, encoding="utf-8")
    print("[OK] appended persist block (app line not found for insertion)")
    raise SystemExit(0)

ins = m.end()
txt2 = txt[:ins] + "\n\n" + BLOCK + "\n" + txt[ins:]
p.write_text(txt2, encoding="utf-8")
print("[OK] inserted VSP_UIREQ_PERSIST_AFTER_REQUEST_V1")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
