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
F = Path("vsp_demo_app.py")
if not F.exists():
    raise SystemExit("[ERR] missing vsp_demo_app.py")

# 0) backup current (even if broken)
broken_bak = F.with_name(F.name + f".bak_broken_{TS}")
broken_bak.write_text(F.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[BACKUP] current =>", broken_bak)

# 1) find latest compiling backup
baks = sorted(F.parent.glob("vsp_demo_app.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
good = None
for b in baks:
    try:
        # test compile backup content by writing temp file
        tmp = F.with_name(f".__tmp_restore_test_{TS}.py")
        tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(tmp), doraise=True)
        tmp.unlink(missing_ok=True)
        good = b
        break
    except Exception:
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass
        continue

if not good:
    raise SystemExit("[ERR] cannot find any compiling backup vsp_demo_app.py.bak_*")

# restore
F.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored vsp_demo_app.py <=", good)

s = F.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_AFTER_REQUEST_OKWRAP_RUNGATE_SUMMARY_V2"
if MARK in s:
    print("[SKIP] marker already present; compile check only")
    py_compile.compile(str(F), doraise=True)
    print("[OK] compile passed")
    raise SystemExit(0)

# 2) detect app variable name (app or application)
m = re.search(r"(?m)^(app|application)\s*=\s*(?:flask\.)?Flask\s*\(", s)
app_var = m.group(1) if m else "app"

block = f"""
# ===================== {MARK} =====================
# Contractize /api/vsp/run_file_allow?path=run_gate_summary.json to always include ok:true (+ rid/run_id)
try:
    from flask import request as _vsp_req
except Exception:
    _vsp_req = None

@{app_var}.after_request
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

# 3) insert safely before if __name__ == "__main__": else append
m_main = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*$", s)
if m_main:
    ins = m_main.start()
    s2 = s[:ins] + block + s[ins:]
else:
    s2 = s.rstrip() + "\n\n" + block

F.write_text(s2, encoding="utf-8")

# compile check
py_compile.compile(str(F), doraise=True)
print("[OK] patched + compile passed. app_var =", app_var)
PY

# restart service
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] restored + after_request ok-wrap v2 applied."
