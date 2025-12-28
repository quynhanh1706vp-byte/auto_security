#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [A] restore latest bak_kics_afterreq =="
BAK="$(ls -1t vsp_demo_app.py.bak_kics_afterreq_* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] no backup found: vsp_demo_app.py.bak_kics_afterreq_*"; exit 2; }
cp -f "$BAK" "$F"
echo "[OK] restored: $BAK -> $F"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_afterreq_v31_${TS}"
echo "[BACKUP] $F.bak_kics_afterreq_v31_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V31 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# helper at top-level
if "_vsp_read_kics_summary" not in t:
    helper = f'''
{TAG}
def _vsp_read_kics_summary(ci_run_dir: str):
    try:
        from pathlib import Path as _P
        fp = _P(ci_run_dir) / "kics" / "kics_summary.json"
        if not fp.exists():
            return None
        import json as _json
        obj = _json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{{}}")
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None
# === END VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V31 ===

'''
    m = re.search(r'(^import .+\n|^from .+ import .+\n)+', t, flags=re.M)
    if m:
        t = t[:m.end()] + "\n" + helper + t[m.end():]
    else:
        t = helper + t

hook = f'''
{TAG}
def _vsp_try_inject_kics_into_payload(payload: dict):
    try:
        ci_dir = payload.get("ci_run_dir") or payload.get("ci_run_dir_abs") or payload.get("run_dir") or payload.get("ci_dir") or ""
        ks = _vsp_read_kics_summary(ci_dir) if ci_dir else None
        if isinstance(ks, dict):
            payload["kics_verdict"] = ks.get("verdict","") or ""
            payload["kics_counts"]  = ks.get("counts",{{}}) if isinstance(ks.get("counts"), dict) else {{}}
            payload["kics_total"]   = int(ks.get("total",0) or 0)
        else:
            payload.setdefault("kics_verdict","")
            payload.setdefault("kics_counts",{{}})
            payload.setdefault("kics_total",0)
    except Exception:
        payload.setdefault("kics_verdict","")
        payload.setdefault("kics_counts",{{}})
        payload.setdefault("kics_total",0)

def vsp_after_request_inject_kics_summary_v31(resp):
    try:
        from flask import request as _req
        path = getattr(_req, "path", "") or ""
        if not (path.startswith("/api/vsp/run_status_v1/") or path.startswith("/api/vsp/run_status_v2/")):
            return resp

        # read JSON body
        raw = resp.get_data(as_text=True) or ""
        s = raw.lstrip()
        if not s:
            return resp
        c0 = s[0]
        if c0 not in ("{{", "["):
            return resp

        import json as _json
        payload = _json.loads(s)
        if not isinstance(payload, dict):
            return resp

        _vsp_try_inject_kics_into_payload(payload)

        resp.set_data(_json.dumps(payload, ensure_ascii=False))
        resp.headers["Content-Type"] = "application/json"
        return resp
    except Exception:
        return resp
# === END VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V31 ===
'''

reg = f"""
{TAG}
try:
    app.after_request(vsp_after_request_inject_kics_summary_v31)
except Exception:
    pass
# === END VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V31 ===
"""

m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', t, flags=re.M)
if m:
    t = t[:m.start()] + hook + "\n" + reg + "\n" + t[m.start():]
else:
    t = t + "\n" + hook + "\n" + reg + "\n"

p.write_text(t, encoding="utf-8")
print("[OK] appended after_request injector v31")
PY

echo "== py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart =="
if command -v systemctl >/dev/null 2>&1 && sudo systemctl list-units --full -all | grep -q '^vsp-ui-gateway\.service'; then
  sudo systemctl restart vsp-ui-gateway
  sudo systemctl is-active vsp-ui-gateway && echo "[OK] vsp-ui-gateway active"
else
  /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
fi
