#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need ss; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS (Gate Story JS chưa có?)"; exit 2; }

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_gate_story_forceinj_${TS}"
echo "[BACKUP] ${F}.bak_gate_story_forceinj_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_GATE_STORY_AFTER_REQUEST_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# find flask app variable name: x = Flask(...)
m = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s)
appv = m.group(1) if m else "app"
print("[INFO] detected flask app var:", appv)

# ensure request import exists
if not re.search(r'(?m)^\s*from\s+flask\s+import\b.*\brequest\b', s):
    # try to extend existing "from flask import ..."
    m2 = re.search(r'(?m)^(from\s+flask\s+import\s+)([^\n]+)$', s)
    if m2:
        line = m2.group(0)
        if "request" not in line:
            newline = line.rstrip() + ", request"
            s = s.replace(line, newline, 1)
            print("[OK] extended import: request")
    else:
        # fallback: prepend new import near top
        s = "from flask import request\n" + s
        print("[OK] prepended import: request")

inject_block = f"""

# --- {MARK} ---
try:
    from flask import request as _vsp_req
except Exception:
    _vsp_req = None

@{appv}.after_request
def _vsp_p1_gate_story_after_request_v1(resp):
    try:
        if _vsp_req is None:
            return resp
        if _vsp_req.path != "/vsp5":
            return resp
        ctype = (resp.headers.get("Content-Type","") or "").lower()
        # accept text/html + utf-8 variants
        if "text/html" not in ctype:
            return resp
        data = resp.get_data(as_text=True)
        if "vsp_dashboard_gate_story_v1.js" in data:
            return resp
        if "</body>" not in data:
            return resp
        script = '<script src="/static/js/vsp_dashboard_gate_story_v1.js?v={{ asset_v }}"></script> <!-- VSP_P1_GATE_STORY_PANEL_V1 -->\\n'
        data2 = data.replace("</body>", script + "</body>")
        resp.set_data(data2)
        # fix content-length for some gunicorn/proxy combos
        resp.headers["Content-Length"] = str(len(data2.encode("utf-8", errors="ignore")))
        return resp
    except Exception:
        return resp
# --- /{MARK} ---
"""

# append before if __name__ == '__main__' if exists, else end
m3 = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m3:
    idx = m3.start()
    s = s[:idx] + inject_block + "\n" + s[idx:]
    print("[OK] injected block before __main__")
else:
    s = s + "\n" + inject_block
    print("[OK] appended block at EOF")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== clean lock/port then restart =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true

bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE /vsp5 include JS? =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" | head -n 5 || true
echo "== PROBE static JS 200? =="
curl -fsS -I "$BASE/static/js/vsp_dashboard_gate_story_v1.js" | sed -n '1,10p' || true
echo "[DONE] force inject gateway v1."
