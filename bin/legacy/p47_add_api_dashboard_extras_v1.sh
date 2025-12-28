#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_dash_extras_${TS}"
echo "[BACKUP] ${APP}.bak_dash_extras_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_DASHBOARD_EXTRAS_V1"
if MARK in s:
    print("[OK] already patched dashboard_extras_v1")
    raise SystemExit(0)

snippet = r'''
# --- VSP_DASHBOARD_EXTRAS_V1 (commercial: fast + stable) ---
try:
    from flask import jsonify, request
except Exception:  # ultra-safe import
    jsonify = None
    request = None

def _vsp_now_iso():
    import datetime
    return datetime.datetime.utcnow().isoformat() + "Z"

def _vsp_build_meta():
    import os, socket
    return {
        "host": socket.gethostname(),
        "pid": os.getpid(),
    }

# Use route() (compatible across Flask versions)
@app.route("/api/vsp/dashboard_extras_v1", methods=["GET"])
def vsp_dashboard_extras_v1():
    """
    Commercial contract:
    - Must respond quickly (no heavy I/O).
    - Must not depend on RID existing.
    - Always returns JSON with ok=true unless catastrophic.
    """
    try:
        rid = ""
        try:
            rid = (request.args.get("rid","") if request else "") or ""
        except Exception:
            rid = ""

        payload = {
            "ok": True,
            "ts": _vsp_now_iso(),
            "rid": rid,
            "extras": {
                "notes": [],
                "degraded": False,
            },
            "build": _vsp_build_meta(),
        }
        if jsonify:
            return jsonify(payload)
        # fallback if jsonify missing
        import json
        return (json.dumps(payload), 200, {"Content-Type":"application/json"})
    except Exception as e:
        # Never crash the worker; return ok=false but still HTTP 200/500-safe
        try:
            if jsonify:
                return jsonify({"ok": False, "error": str(e), "ts": _vsp_now_iso()}), 200
        except Exception:
            pass
        import json
        return (json.dumps({"ok": False, "error": str(e)}), 200, {"Content-Type":"application/json"})
# --- /VSP_DASHBOARD_EXTRAS_V1 ---
'''.lstrip("\n")

# Insert before __main__ guard if present; else append end
m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s2 = s[:m.start()] + "\n\n" + snippet + "\n\n" + s[m.start():]
else:
    s2 = s.rstrip() + "\n\n" + snippet + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched dashboard_extras_v1")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile PASS"

# restart service if present
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart vsp-ui-8910.service || true
fi

# quick probe
curl -sS --connect-timeout 2 --max-time 6 "http://127.0.0.1:8910/api/vsp/dashboard_extras_v1" | head -c 300; echo
echo "[OK] done"
