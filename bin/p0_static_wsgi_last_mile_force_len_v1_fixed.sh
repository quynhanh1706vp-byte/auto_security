#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_wsgi_static_last_${TS}"
echo "[BACKUP] ${F}.bak_wsgi_static_last_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_WSGI_STATIC_LAST_MILE_FORCE_LEN_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# detect flask app var: x = Flask(...)
m = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s)
appv = m.group(1) if m else "app"
print("[INFO] flask app var:", appv)

block_tpl = r"""
# --- __MARK__ ---
def _vsp_p0_wsgi_static_last_mile_force_len_v1(wsgi_app):
    import mimetypes
    from pathlib import Path

    base_dir = Path(__file__).resolve().parent
    static_dir = (base_dir / "static").resolve()

    def _app(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()

            if not path.startswith("/static/"):
                return wsgi_app(environ, start_response)

            rel = path[len("/static/"):]
            fp = (static_dir / rel).resolve()

            # prevent traversal
            if static_dir not in fp.parents and fp != static_dir:
                return wsgi_app(environ, start_response)
            if not fp.is_file():
                return wsgi_app(environ, start_response)

            data = fp.read_bytes()

            ctype, _ = mimetypes.guess_type(str(fp))
            if not ctype:
                ext = fp.suffix.lower()
                if ext == ".js":
                    ctype = "text/javascript"
                elif ext == ".css":
                    ctype = "text/css"
                else:
                    ctype = "application/octet-stream"

            headers = [
                ("Content-Type", (ctype + "; charset=utf-8") if ctype.startswith("text/") else ctype),
                ("Content-Length", str(len(data))),
                ("Cache-Control", "no-cache"),
                ("Content-Disposition", "inline; filename=" + fp.name),
            ]

            start_response("200 OK", headers)
            if method == "HEAD":
                return [b""]
            return [data]

        except Exception:
            return wsgi_app(environ, start_response)

    return _app

try:
    __APPV__.wsgi_app = _vsp_p0_wsgi_static_last_mile_force_len_v1(__APPV__.wsgi_app)
except Exception:
    pass
# --- /__MARK__ ---
"""

block = block_tpl.replace("__MARK__", MARK).replace("__APPV__", appv)

# append at EOF (strongest)
s2 = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart clean :8910 =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE HEAD (Content-Length must be >0) =="
curl -fsS -I "$BASE/static/js/vsp_dashboard_gate_story_v1.js" | sed -n '1,15p'
echo "== PROBE GET size =="
curl -fsS "$BASE/static/js/vsp_dashboard_gate_story_v1.js" | wc -c
echo "[DONE] WSGI last-mile static fix (fixed) applied."
