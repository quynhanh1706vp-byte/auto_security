#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need head; need grep; need curl

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_wsgiw_reset_${TS}"
echo "[BACKUP] ${WSGI}.bak_wsgiw_reset_${TS}"

echo "== [1] Hard clean known bad middleware blocks + re-attach ONE safe middleware =="
"$PY" - <<'PY'
from pathlib import Path
import re, time, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Remove any prior injected blocks (multiple generations) to avoid syntax/indent collisions
markers = [
  ("### === CIO MIME FIX (AUTO) ===", "### === END CIO MIME FIX (AUTO) ==="),
  ("### === CIO JS NOCACHE (AUTO) ===", "### === END CIO JS NOCACHE (AUTO) ==="),
  ("### === CIO SAFE JS HEADERS MW (AUTO) ===", "### === END CIO SAFE JS HEADERS MW (AUTO) ==="),
  ("### === CIO RUNS_INDEX ALIAS (AUTO) ===", "### === END CIO RUNS_INDEX ALIAS (AUTO) ==="),  # keep if you want; here we don't touch app.py anyway
  ("### === CIO RUNS_FS ALIAS (AUTO) ===", "### === END CIO RUNS_FS ALIAS (AUTO) ==="),
]

orig = s
for a,b in markers:
    s = re.sub(rf"{re.escape(a)}.*?{re.escape(b)}\n?", "", s, flags=re.S)

# Remove stray wrap lines that call removed functions
s = re.sub(r"(?m)^\s*try:\s*\n\s*application\s*=\s*_cio_[a-zA-Z0-9_]+\([^\n]*\)\s*\n\s*except Exception:\s*\n(?:\s*try:\s*\n\s*application\s*=\s*_cio_[a-zA-Z0-9_]+\([^\n]*\)\s*\n\s*except Exception:\s*\n\s*pass\s*\n|\s*pass\s*\n)", "", s)

# Also remove any single-line wrappers left behind
s = re.sub(r"(?m)^\s*application\s*=\s*_cio_[a-zA-Z0-9_]+\([^\n]*\)\s*$", "", s)

SAFE = r'''
### === CIO SAFE JS HEADERS MW (AUTO) ===
# Commercial-safe: ensure JS always has JS MIME + no-store so browser won't cache stale broken assets.
def _cio_safe_js_headers_mw(app):
    def _wrap(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        def _sr(status, headers, exc_info=None):
            try:
                if path.endswith(".js"):
                    h=[]
                    ct=None
                    for k,v in headers:
                        lk=k.lower()
                        if lk=="content-type":
                            ct=v
                        if lk=="cache-control":
                            continue
                        h.append((k,v))
                    if ct and "application/json" in ct.lower():
                        h=[(k,("application/javascript; charset=utf-8" if k.lower()=="content-type" else v)) for (k,v) in h]
                    h.append(("Cache-Control","no-store"))
                    headers=h
            except Exception:
                pass
            return start_response(status, headers, exc_info)
        return app(environ, _sr)
    return _wrap
### === END CIO SAFE JS HEADERS MW (AUTO) ===
'''.strip("\n") + "\n"

WRAP = r'''
try:
    application = _cio_safe_js_headers_mw(application)
except Exception:
    try:
        application = _cio_safe_js_headers_mw(app)
    except Exception:
        pass
'''.strip("\n") + "\n"

# Append safe block at end (idempotent)
s = s.rstrip() + "\n\n" + SAFE + "\n" + WRAP

bak = p.with_name(p.name + f".bak_resetclean_{time.strftime('%Y%m%d_%H%M%S')}")
bak.write_text(orig, encoding="utf-8")
p.write_text(s, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] wsgi reset + py_compile ok; backup:", bak.name)
PY

echo
echo "== [2] Restart service; show status/journal if failed =="
set +e
sudo systemctl restart "$SVC"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[ERR] restart failed. Status + journal:"
  sudo systemctl status "$SVC" --no-pager -l | sed -n '1,140p' || true
  sudo journalctl -u "$SVC" -n 200 --no-pager || true
  exit 5
fi
echo "[OK] restarted $SVC"

echo
echo "== [3] Smoke headers (JS must be JS, no-store) =="
curl -fsSI "$BASE/static/js/vsp_bundle_tabs5_v1.js" | tr -d '\r' | egrep -i 'HTTP/|content-type|cache-control' || true
curl -fsSI "$BASE/static/js/vsp_dashboard_luxe_v1.js" | tr -d '\r' | egrep -i 'HTTP/|content-type|cache-control' || true
echo "[DONE] Now Ctrl+Shift+R on /vsp5."
