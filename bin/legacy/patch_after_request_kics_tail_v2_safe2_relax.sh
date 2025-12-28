#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_afterreq_kics_tail_v2safe2_${TS}"
echo "[BACKUP] $F.bak_afterreq_kics_tail_v2safe2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path
p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# find function body we inserted
m = re.search(r"(?ms)^(\s*)def _vsp__after_request_kics_tail\(resp\):\s*\n(.*?)^\1try:\s*\n^\1\s*app\.after_request\(_vsp__after_request_kics_tail\)\s*\n", t)
if not m:
    raise SystemExit("[ERR] cannot locate _vsp__after_request_kics_tail() block (V2_SAFE).")

ind = m.group(1)

new_func = f"""{ind}def _vsp__after_request_kics_tail(resp):
{ind}    try:
{ind}        import json
{ind}        from flask import request
{ind}        if not request.path.startswith("/api/vsp/run_status_v1/"):
{ind}            return resp
{ind}        # debug header: prove hook executed
{ind}        try:
{ind}            resp.headers["X-VSP-AFTERREQ"] = "1"
{ind}        except Exception:
{ind}            pass
{ind}        rid = request.path.rsplit("/", 1)[-1]
{ind}        data = ""
{ind}        try:
{ind}            data = resp.get_data(as_text=True) or ""
{ind}        except Exception:
{ind}            return resp
{ind}        try:
{ind}            obj = json.loads(data) if data.strip() else {{}}
{ind}        except Exception:
{ind}            return resp
{ind}        if not isinstance(obj, dict):
{ind}            return resp
{ind}        stage = str(obj.get("stage_name") or "").lower()
{ind}        ci = str(obj.get("ci_run_dir") or "")
{ind}        if not ci:
{ind}            ci = _vsp__load_ci_dir_from_state(rid)
{ind}        if ci and ("kics" in stage):
{ind}            kt = _vsp__kics_tail_from_ci(ci)
{ind}            if kt:
{ind}                obj["kics_tail"] = kt
{ind}                resp.set_data(json.dumps(obj, ensure_ascii=False))
{ind}                try:
{ind}                    resp.headers["Content-Length"] = str(len(resp.get_data()))
{ind}                    resp.headers["X-VSP-KICS-TAIL"] = "1"
{ind}                except Exception:
{ind}                    pass
{ind}        return resp
{ind}    except Exception:
{ind}        return resp
"""

# replace only the function definition block
t2 = re.sub(r"(?ms)^(\s*)def _vsp__after_request_kics_tail\(resp\):\s*\n.*?^\1except Exception:\s*\n^\1\s*return resp\s*\n", new_func, t, count=1)
p.write_text(t2, encoding="utf-8")
print("[OK] patched to V2_SAFE2 relax + debug headers")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

pkill -f "vsp_demo_app.py" >/dev/null 2>&1 || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz || true
echo
