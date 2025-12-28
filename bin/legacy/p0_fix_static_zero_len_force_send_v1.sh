#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_static_zerolen_${TS}"
echo "[BACKUP] ${F}.bak_fix_static_zerolen_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_FIX_STATIC_ZERO_LEN_FORCE_SEND_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# detect flask app var (x = Flask(...))
m = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s)
appv = m.group(1) if m else "app"
print("[INFO] detected flask app var:", appv)

# ensure request import exists
if not re.search(r'(?m)^\s*from\s+flask\s+import\b.*\brequest\b', s):
    m2 = re.search(r'(?m)^(from\s+flask\s+import\s+)([^\n]+)$', s)
    if m2:
        line = m2.group(0)
        if "request" not in line:
            s = s.replace(line, line.rstrip() + ", request", 1)
            print("[OK] extended flask import: request")
    else:
        s = "from flask import request\n" + s
        print("[OK] prepended import: request")

# ensure pathlib import exists (often already)
if "from pathlib import Path" not in s and "import pathlib" not in s:
    s = "from pathlib import Path\n" + s
    print("[OK] prepended import: Path")

block = f"""

# --- {MARK} ---
try:
    from flask import request as _vsp_req
except Exception:
    _vsp_req = None

@{appv}.after_request
def _vsp_p0_fix_static_zero_len_force_send_v1(resp):
    try:
        if _vsp_req is None:
            return resp
        # only for /static/*
        path = getattr(_vsp_req, "path", "") or ""
        if not path.startswith("/static/"):
            return resp
        if resp.status_code != 200:
            return resp

        # If Content-Length is 0 (bug), force load from disk.
        cl = resp.headers.get("Content-Length", "")
        if str(cl).strip() not in ("0", ""):
            return resp

        # map URL -> file path under ./static
        rel = path[len("/static/"):]
        static_dir = Path(__file__).resolve().parent / "static"
        fp = (static_dir / rel).resolve()

        # prevent traversal
        if static_dir.resolve() not in fp.parents and fp != static_dir.resolve():
            return resp
        if not fp.is_file():
            return resp

        data = fp.read_bytes()
        # HEAD should return empty body but correct Content-Length
        if (_vsp_req.method or "").upper() == "HEAD":
            resp.set_data(b"")
            resp.headers["Content-Length"] = str(len(data))
            return resp

        resp.set_data(data)
        resp.headers["Content-Length"] = str(len(data))
        return resp
    except Exception:
        return resp
# --- /{MARK} ---
"""

# append before __main__ if exists
m3 = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m3:
    s = s[:m3.start()] + block + "\n" + s[m3.start():]
    print("[OK] injected block before __main__")
else:
    s = s + "\n" + block
    print("[OK] appended block at EOF")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart clean :8910 =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE static size =="
curl -fsS "$BASE/static/js/vsp_dashboard_gate_story_v1.js" | wc -c
echo "== PROBE vsp5 includes gate story =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" | head -n 3 || true
echo "[DONE] static zero-len fix applied."
