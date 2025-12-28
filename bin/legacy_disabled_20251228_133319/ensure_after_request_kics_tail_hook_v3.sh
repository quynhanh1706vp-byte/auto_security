#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_afterreq_kics_tail_v3_${TS}"
echo "[BACKUP] $F.bak_afterreq_kics_tail_v3_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_AFTER_REQUEST_KICS_TAIL_HOOK_V3 ==="
if TAG in t:
    print("[OK] already has V3 hook")
    raise SystemExit(0)

# find app creation line
m = re.search(r"(?m)^(app\s*=\s*Flask\([^\n]*\)\s*)$", t)
if not m:
    # fallback: any "Flask(" assignment
    m = re.search(r"(?m)^(app\s*=\s*Flask\([^\n]*\)\s*)$", t)
if not m:
    raise SystemExit("[ERR] cannot find 'app = Flask(...)' to insert hook after")

ins_at = m.end()

block = r'''
# === VSP_AFTER_REQUEST_KICS_TAIL_HOOK_V3 ===
def _vsp__load_ci_dir_from_state_v3(req_id: str) -> str:
    try:
        import json
        from pathlib import Path
        base = Path(__file__).resolve().parent
        cands = [
            base / 'out_ci' / 'uireq_v1' / (req_id + '.json'),
            base / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),
        ]
        for fp in cands:
            if fp.exists():
                txt = fp.read_text(encoding='utf-8', errors='ignore') or ''
                j = json.loads(txt) if txt.strip() else {}
                ci = str(j.get('ci_run_dir') or '')
                if ci:
                    return ci
    except Exception:
        pass
    return ""

def _vsp__kics_tail_from_ci_v3(ci: str, max_bytes: int = 65536, max_chars: int = 4096) -> str:
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

@app.after_request
def _vsp__after_request_kics_tail_v3(resp):
    try:
        import json
        from flask import request

        # debug header: prove hook executed
        try:
            resp.headers["X-VSP-AFTERREQ"] = "V3"
        except Exception:
            pass

        if not request.path.startswith("/api/vsp/run_status_v1/"):
            return resp

        rid = request.path.rsplit("/", 1)[-1]
        data = ""
        try:
            data = resp.get_data(as_text=True) or ""
        except Exception:
            return resp

        try:
            obj = json.loads(data) if data.strip() else {}
        except Exception:
            return resp

        if not isinstance(obj, dict):
            return resp

        stage = str(obj.get("stage_name") or "").lower()
        if "kics" not in stage:
            return resp

        ci = str(obj.get("ci_run_dir") or "")
        if not ci:
            ci = _vsp__load_ci_dir_from_state_v3(rid)

        if ci:
            kt = _vsp__kics_tail_from_ci_v3(ci)
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
# === END VSP_AFTER_REQUEST_KICS_TAIL_HOOK_V3 ===
'''

t2 = t[:ins_at] + "\n" + block + t[ins_at:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted V3 hook right after app = Flask(...)")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

pkill -f "vsp_demo_app.py" >/dev/null 2>&1 || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz || true
echo
