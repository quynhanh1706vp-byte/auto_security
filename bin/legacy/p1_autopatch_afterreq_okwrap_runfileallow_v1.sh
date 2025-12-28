#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true

python3 - <<'PY'
from pathlib import Path
import time, re, py_compile

TS = time.strftime("%Y%m%d_%H%M%S")
MARK = "VSP_P1_AFTERREQ_OKWRAP_RUNFILEALLOW_V1"
ROUTE = "/api/vsp/run_file_allow"

root = Path(".")
cands = []
for p in root.rglob("*.py"):
    if any(x in p.parts for x in (".venv","venv","node_modules","out","bin")):
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if ROUTE in s:
        cands.append(p)

if not cands:
    raise SystemExit(f"[ERR] cannot find '{ROUTE}' in any *.py under {root.resolve()}")

# prefer gateway-ish files first
prio = {"wsgi_vsp_ui_gateway.py": 0, "vsp_demo_app.py": 1}
cands.sort(key=lambda p: (prio.get(p.name, 9), len(str(p)), str(p)))

print("[INFO] candidates:")
for p in cands[:12]:
    print(" -", p)

patched = []
for p in cands:
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue

    bak = p.with_name(p.name + f".bak_afterreq_runfileallow_{TS}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak)

    block = f"""

# ===================== {MARK} =====================
# Contractize {ROUTE}?path=run_gate_summary.json / run_gate.json => always include ok:true (+ rid/run_id)
def _vsp_after_request_okwrap_runfileallow(resp):
    try:
        from flask import request as _req
        if _req.path != "{ROUTE}":
            return resp
        _path = _req.args.get("path", "") or ""
        if not (str(_path).endswith("run_gate_summary.json") or str(_path).endswith("run_gate.json")):
            return resp

        _rid = _req.args.get("rid", "") or ""
        txt = resp.get_data(as_text=True)

        import json as _json
        j = _json.loads(txt)
        if isinstance(j, dict):
            j.setdefault("ok", True)
            if _rid:
                j.setdefault("rid", _rid)
                j.setdefault("run_id", _rid)
            out = _json.dumps(j, ensure_ascii=False)
            resp.set_data(out)
            resp.headers["Content-Type"] = "application/json; charset=utf-8"
            resp.headers["Cache-Control"] = "no-cache"
            resp.headers["Content-Length"] = str(len(resp.get_data()))
        return resp
    except Exception:
        return resp

# register to whichever Flask app exists in this module
try:
    _APP = globals().get("app") or globals().get("application")
    if _APP is not None and hasattr(_APP, "after_request"):
        _APP.after_request(_vsp_after_request_okwrap_runfileallow)
except Exception:
    pass
# ===================== /{MARK} =====================

"""

    # insert safely before __main__ if present, else append
    m_main = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*$", s)
    if m_main:
        s2 = s[:m_main.start()] + block + s[m_main.start():]
    else:
        s2 = s.rstrip() + "\n" + block

    p.write_text(s2, encoding="utf-8")

    # compile check
    py_compile.compile(str(p), doraise=True)
    print("[OK] patched+compiled:", p)
    patched.append(p)

if not patched:
    print("[WARN] nothing patched (marker already present everywhere).")
else:
    print("[DONE] patched files:", [str(x) for x in patched])
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] service restarted (if systemd). Now verify with curl."
