#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_afterreq_v32_${TS}"
echo "[BACKUP] $F.bak_kics_afterreq_v32_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V32 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# Ensure helper exists (top-level). If you already have _vsp_read_kics_summary, keep it.
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
# === END VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V32 ===

'''
    m = re.search(r'(^import .+\n|^from .+ import .+\n)+', t, flags=re.M)
    if m:
        t = t[:m.end()] + "\n" + helper + t[m.end():]
    else:
        t = helper + t

hook = f'''
{TAG}
def _vsp_guess_ci_run_dir_from_rid(rid: str):
    """
    Best-effort resolve CI run dir when API payload misses ci_run_dir.
    We keep it cheap by using a few bounded glob patterns.
    """
    try:
        import glob, os
        if not rid:
            return None
        rid_norm = rid[4:] if rid.startswith("RUN_") else rid  # RUN_VSP_CI_* -> VSP_CI_*
        pats = [
            f"/home/test/Data/*/out_ci/{rid_norm}",
            f"/home/test/Data/*/*/out_ci/{rid_norm}",
            f"/home/test/Data/*/out/{rid_norm}",
            f"/home/test/Data/*/*/out/{rid_norm}",
        ]
        for pat in pats:
            for g in glob.glob(pat):
                if os.path.isdir(g):
                    return g
        return None
    except Exception:
        return None

def _vsp_try_inject_kics_into_payload_v32(payload: dict, req_path: str):
    try:
        # resolve ci_run_dir if missing
        ci_dir = payload.get("ci_run_dir") or payload.get("ci_run_dir_abs") or payload.get("run_dir") or payload.get("ci_dir") or ""
        if not ci_dir:
            rid = payload.get("rid_norm") or payload.get("run_id") or payload.get("request_id") or ""
            if not rid and req_path:
                rid = req_path.rsplit("/", 1)[-1]
            g = _vsp_guess_ci_run_dir_from_rid(rid)
            if g:
                payload["ci_run_dir"] = g
                ci_dir = g

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

def vsp_after_request_inject_kics_summary_v32(resp):
    try:
        from flask import request as _req
        path = getattr(_req, "path", "") or ""
        if not (path.startswith("/api/vsp/run_status_v1/") or path.startswith("/api/vsp/run_status_v2/")):
            return resp

        raw = resp.get_data(as_text=True) or ""
        s = raw.lstrip()
        if not s:
            return resp

        c0 = s[0]
        # IMPORTANT: correct JSON detection
        if c0 not in ("{{", "["):  # placeholder, will be replaced below
            return resp
    except Exception:
        return resp
# === END VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V32 ===
'''

# Replace the placeholder JSON detection line to correct one: ("{","[")
hook = hook.replace('if c0 not in ("{{", "[")', 'if c0 not in ("{", "[")')

# Now add the rest of function body after JSON detection
hook2 = f'''
{TAG}
# continuation (safe to append right after the placeholder block above)
'''

# Instead of complex surgery, we’ll patch by appending a complete, correct function definition block (v32b),
# and register it after app creation. This avoids partial function edits.
v32b = f'''
{TAG}
def vsp_after_request_inject_kics_summary_v32b(resp):
    try:
        from flask import request as _req
        path = getattr(_req, "path", "") or ""
        if not (path.startswith("/api/vsp/run_status_v1/") or path.startswith("/api/vsp/run_status_v2/")):
            return resp

        import json as _json
        raw = resp.get_data(as_text=True) or ""
        s = raw.lstrip()
        if not s:
            return resp
        c0 = s[0]
        if c0 not in ("{{","["):
            return resp
        payload = _json.loads(s)
        if not isinstance(payload, dict):
            return resp

        _vsp_try_inject_kics_into_payload_v32(payload, path)

        resp.set_data(_json.dumps(payload, ensure_ascii=False))
        resp.headers["Content-Type"] = "application/json"
        return resp
    except Exception:
        return resp
# === END VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V32 ===
'''
v32b = v32b.replace('if c0 not in ("{{","[")', 'if c0 not in ("{","[")')

reg = f"""
{TAG}
try:
    app.after_request(vsp_after_request_inject_kics_summary_v32b)
except Exception:
    pass
# === END VSP_AFTER_REQUEST_INJECT_KICS_SUMMARY_V32 ===
"""

m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', t, flags=re.M)
if m:
    t = t[:m.start()] + "\n" + hook + "\n" + v32b + "\n" + reg + "\n" + t[m.start():]
else:
    t = t + "\n" + hook + "\n" + v32b + "\n" + reg + "\n"

p.write_text(t, encoding="utf-8")
print("[OK] appended v32 injector (with ci_run_dir guess + correct JSON check)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart 8910 =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh

echo "== verify =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
