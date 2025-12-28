#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

TS = time.strftime("%Y%m%d_%H%M%S")
MARK = "VSP_P1_AFTER_REQUEST_OKWRAP_RUNGATE_SUMMARY_V1"

F = Path("vsp_demo_app.py")
if not F.exists():
    raise SystemExit("[ERR] missing vsp_demo_app.py (run in /home/test/Data/SECURITY_BUNDLE/ui)")

s = F.read_text(encoding="utf-8", errors="replace")
bak = F.with_name(F.name + f".bak_afterreq_okwrap_{TS}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

if MARK in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# Find app variable name: app = Flask(...) or application = Flask(...)
m = re.search(r"(?m)^(?P<var>app|application)\s*=\s*(?:flask\.)?Flask\s*\(", s)
if not m:
    raise SystemExit("[ERR] cannot find Flask app creation line like: app = Flask(...)" )

var = m.group("var")
insert_pos = m.end()

block = f"""

# ===================== {MARK} =====================
# Contractize run_gate_summary.json/run_gate.json to always include ok:true (+ rid/run_id)
try:
    from flask import request as _vsp_req
except Exception:
    _vsp_req = None

@{var}.after_request
def _vsp_after_request_okwrap_rungate_summary(resp):
    try:
        if _vsp_req is None:
            return resp
        if _vsp_req.path != "/api/vsp/run_file_allow":
            return resp
        p = _vsp_req.args.get("path", "") or ""
        if not (str(p).endswith("run_gate_summary.json") or str(p).endswith("run_gate.json")):
            return resp

        rid = _vsp_req.args.get("rid", "") or ""
        # best-effort: parse JSON even if content-type isn't application/json
        txt = resp.get_data(as_text=True)
        import json as _json
        j = _json.loads(txt)
        if isinstance(j, dict):
            j.setdefault("ok", True)
            if rid:
                j.setdefault("rid", rid)
                j.setdefault("run_id", rid)
            out = _json.dumps(j, ensure_ascii=False)
            resp.set_data(out)
            resp.headers["Content-Type"] = "application/json; charset=utf-8"
            resp.headers["Cache-Control"] = "no-cache"
            resp.headers["Content-Length"] = str(len(resp.get_data()))
        return resp
    except Exception:
        return resp

# ===================== /{MARK} =====================

"""

s2 = s[:insert_pos] + block + s[insert_pos:]
F.write_text(s2, encoding="utf-8")
py_compile.compile(str(F), doraise=True)
print("[OK] patched:", F, "app_var=", var)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] after_request ok-wrap applied."
