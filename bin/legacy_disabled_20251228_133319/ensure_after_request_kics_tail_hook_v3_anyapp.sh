#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_afterreq_kics_tail_v3any_${TS}"
echo "[BACKUP] $F.bak_afterreq_kics_tail_v3any_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_AFTER_REQUEST_KICS_TAIL_HOOK_V3_ANYAPP ==="
if TAG in t:
    print("[OK] already has V3_ANYAPP hook")
    raise SystemExit(0)

# 0) cleanup older broken/partial attempts (best-effort)
t = re.sub(r"(?s)# === VSP_AFTER_REQUEST_KICS_TAIL_V1 ===.*?# === END VSP_AFTER_REQUEST_KICS_TAIL_V1 ===\s*", "", t)
t = re.sub(r"(?s)# === VSP_AFTER_REQUEST_KICS_TAIL_V2_SAFE.*?# === END VSP_AFTER_REQUEST_KICS_TAIL_V2_SAFE.*?\s*", "", t)
t = re.sub(r"(?s)# === VSP_AFTER_REQUEST_KICS_TAIL_HOOK_V3 ===.*?# === END VSP_AFTER_REQUEST_KICS_TAIL_HOOK_V3 ===\s*", "", t)

# 1) detect app variable name
appvar = None

# (a) from route decorator: @X.route(...)
m = re.search(r"(?m)^\s*@\s*([A-Za-z_]\w*)\.(?:route|get|post|put|delete|patch)\s*\(", t)
if m:
    appvar = m.group(1)

# (b) from call style: X.route(...)
if not appvar:
    m = re.search(r"(?m)^\s*([A-Za-z_]\w*)\.(?:route|get|post|put|delete|patch)\s*\(", t)
    if m:
        appvar = m.group(1)

# (c) from Flask assignment: X = Flask(...)
if not appvar:
    m = re.search(r"(?m)^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(", t)
    if m:
        appvar = m.group(1)

# fallback: try common name
if not appvar:
    # if the file uses `app` routes elsewhere without matching above
    if re.search(r"(?m)^\s*@\s*app\.(?:route|get|post|put|delete|patch)\s*\(", t) or re.search(r"(?m)^\s*app\.(?:route|get|post|put|delete|patch)\s*\(", t):
        appvar = "app"

if not appvar:
    raise SystemExit("[ERR] cannot infer Flask app variable name (no @X.route / X.route / X=Flask found)")

# 2) choose insertion point: before if __name__ == '__main__' else EOF
m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*$", t)
ins_at = m.start() if m else len(t)

block = f'''
{TAG}
def _vsp__load_ci_dir_from_state_v3_any(req_id: str) -> str:
    try:
        import json
        from pathlib import Path
        base = Path(__file__).resolve().parent
        cands = [
            base / 'out_ci' / 'uireq_v1' / (req_id + '.json'),
            base / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),
            base / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),  # keep duplicate harmless
        ]
        for fp in cands:
            if fp.exists():
                txt = fp.read_text(encoding='utf-8', errors='ignore') or ''
                j = json.loads(txt) if txt.strip() else {{}}
                ci = str(j.get('ci_run_dir') or '')
                if ci:
                    return ci
    except Exception:
        pass
    return ""

def _vsp__kics_tail_from_ci_v3_any(ci: str, max_bytes: int = 65536, max_chars: int = 4096) -> str:
    try:
        import os
        from pathlib import Path
        NL = chr(10)
        klog = os.path.join(ci, 'kics', 'kics.log')
        if not os.path.exists(klog):
            return ""
        rawb = Path(klog).read_bytes()
        if len(rawb) > max_bytes:
            rawb = rawb[-max_bytes:]
        raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)

        hb = ""
        for ln in reversed(raw.splitlines()):
            if "][HB]" in ln and "[KICS_V" in ln:
                hb = ln.strip()
                break

        lines = [x for x in raw.splitlines() if x.strip()]
        tail = NL.join(lines[-30:])
        if hb and (hb not in tail):
            tail = hb + NL + tail
        return tail[-max_chars:]
    except Exception:
        return ""

def _vsp__after_request_kics_tail_v3_any(resp):
    try:
        import json
        from flask import request

        # prove hook executed
        try:
            resp.headers["X-VSP-AFTERREQ"] = "V3_ANYAPP"
        except Exception:
            pass

        if not request.path.startswith("/api/vsp/run_status_v1/"):
            return resp

        rid = request.path.rsplit("/", 1)[-1]

        try:
            data = resp.get_data(as_text=True) or ""
        except Exception:
            return resp

        try:
            obj = json.loads(data) if data.strip() else {{}}
        except Exception:
            return resp

        if not isinstance(obj, dict):
            return resp

        stage = str(obj.get("stage_name") or "").lower()
        if "kics" not in stage:
            return resp

        ci = str(obj.get("ci_run_dir") or "")
        if not ci:
            ci = _vsp__load_ci_dir_from_state_v3_any(rid)

        if ci:
            kt = _vsp__kics_tail_from_ci_v3_any(ci)
            if kt:
                obj["kics_tail"] = kt
                resp.set_data(json.dumps(obj, ensure_ascii=False))
                try:
                    resp.headers["Content-Length"] = str(len(resp.get_data()))
                    resp.headers["X-VSP-KICS-TAIL"] = "1"
                except Exception:
                    pass
        return resp
    except Exception:
        return resp

try:
    {appvar}.after_request(_vsp__after_request_kics_tail_v3_any)
    try:
        print("[VSP][AFTERREQ] registered kics_tail hook on {appvar}")
    except Exception:
        pass
except Exception as _e:
    try:
        print("[VSP][AFTERREQ] register failed:", repr(_e))
    except Exception:
        pass
# === END VSP_AFTER_REQUEST_KICS_TAIL_HOOK_V3_ANYAPP ===
'''

t2 = t[:ins_at] + "\n" + block + "\n" + t[ins_at:]
p.write_text(t2, encoding="utf-8")
print(f"[OK] inserted V3_ANYAPP hook near end. appvar={appvar}")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

pkill -f "vsp_demo_app.py" >/dev/null 2>&1 || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz || true
echo
