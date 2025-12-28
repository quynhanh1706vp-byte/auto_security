#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_reorder_static_cl_${TS}"
echo "[BACKUP] ${F}.bak_reorder_static_cl_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_FIX_STATIC_ZERO_LEN_FORCE_SEND_V1"

# detect flask app var: X = Flask(...)
m = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s)
appv = m.group(1) if m else "app"
print("[INFO] flask app var:", appv)

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

# remove old block if exists
pat = re.compile(rf"\n?# --- {MARK} ---.*?# --- /{MARK} ---\n?", re.S)
s, n = pat.subn("\n", s)
if n:
    print("[OK] removed old block:", n)

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
        path = getattr(_vsp_req, "path", "") or ""
        if not path.startswith("/static/"):
            return resp
        if resp.status_code != 200:
            return resp

        # If Content-Length is wrong (0/missing), fix it.
        cl = (resp.headers.get("Content-Length") or "").strip()

        # Read body length if already present
        try:
            body = resp.get_data()  # bytes
        except Exception:
            body = b""

        # If we already have body but CL=0, set correct
        if body and cl in ("", "0"):
            resp.headers["Content-Length"] = str(len(body))
            return resp

        # If body empty but CL=0, load from disk as a fallback
        if cl in ("", "0"):
            from pathlib import Path as _P
            static_dir = _P(__file__).resolve().parent / "static"
            rel = path[len("/static/"):]
            fp = (static_dir / rel).resolve()
            if static_dir.resolve() not in fp.parents and fp != static_dir.resolve():
                return resp
            if not fp.is_file():
                return resp
            data = fp.read_bytes()

            if (_vsp_req.method or "").upper() == "HEAD":
                resp.set_data(b"")
                resp.headers["Content-Length"] = str(len(data))
                return resp

            resp.set_data(data)
            resp.headers["Content-Length"] = str(len(data))
            return resp

        return resp
    except Exception:
        return resp
# --- /{MARK} ---
"""

# insert block immediately after the Flask app creation line
app_line = re.search(rf"(?m)^\s*{re.escape(appv)}\s*=\s*Flask\s*\([^\n]*\)\s*$", s)
if not app_line:
    # fallback: after first occurrence of "Flask("
    app_line = re.search(r"(?m)^\s*[A-Za-z_]\w*\s*=\s*Flask\s*\([^\n]*\)\s*$", s)

if not app_line:
    print("[ERR] cannot locate app = Flask(...) line to inject right after.")
    raise SystemExit(2)

idx = app_line.end()
s2 = s[:idx] + "\n\n" + block + "\n" + s[idx:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted block right after app creation (runs LAST).")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart clean :8910 =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE GET headers (expect Content-Length > 0) =="
curl -fsS -D - "$BASE/static/js/vsp_dashboard_gate_story_v1.js" -o /dev/null | sed -n '1,15p'
echo "== PROBE HEAD headers (expect Content-Length > 0) =="
curl -fsS -I "$BASE/static/js/vsp_dashboard_gate_story_v1.js" | sed -n '1,15p'
echo "== PROBE /vsp5 includes gate story =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" | head -n 3 || true
echo "[DONE] reorder + static Content-Length fix applied."
