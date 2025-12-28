#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sudo; need systemctl; need curl; need ss

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || err "missing $F (expected UI gateway entrypoint here)"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_apihitgw_${TS}"
ok "backup: ${F}.bak_apihitgw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")
MARK = "VSP_P0_API_HITLOG_WSGI_V1N3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

mw = r'''
# VSP_P0_API_HITLOG_WSGI_V1N3: log /api/vsp/* hits (no gunicorn accesslog required)
def __vsp_api_hitlog_wrap(app):
    try:
        def _wsgi(environ, start_response):
            try:
                path = (environ.get("PATH_INFO") or "")
                if path.startswith("/api/vsp/"):
                    qs = environ.get("QUERY_STRING") or ""
                    # normalize noisy ts=
                    qs = re.sub(r'(^|&)ts=\d+', r'\1ts=', qs)
                    full = path + (("?" + qs) if qs else "")
                    method = environ.get("REQUEST_METHOD") or "GET"
                    print(f"[VSP_API_HIT] {method} {full}", flush=True)
            except Exception:
                pass
            return app(environ, start_response)
        return _wsgi
    except Exception:
        return app
'''

# ensure import re
if not re.search(r'^\s*import\s+re\s*$', s, flags=re.M):
    s = "import re\n" + s

# append middleware helper near end (safe)
s = s + "\n\n" + mw + "\n"

# now wrap common exported objects if present: application / app
# We do it at very end, guarded.
wrap_snip = r'''
try:
    # wrap common WSGI exports
    if "application" in globals() and callable(globals().get("application")):
        application = __vsp_api_hitlog_wrap(application)
    if "app" in globals() and hasattr(globals().get("app"), "wsgi_app"):
        app.wsgi_app = __vsp_api_hitlog_wrap(app.wsgi_app)
except Exception:
    pass
'''
s = s + "\n" + wrap_snip + "\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK:", str(p))
PY

ok "py_compile OK: $F"

# restart + wait for 8910
SVC="vsp-ui-8910.service"
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC"

for i in $(seq 1 60); do
  ss -ltnp | grep -q ':8910' && break
  sleep 0.25
done
ss -ltnp | grep -q ':8910' || err "8910 not listening after restart"

BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null || true
curl -fsS "$BASE/api/vsp/rid_latest" >/dev/null || true
curl -fsS "$BASE/api/vsp/release_latest" >/dev/null || true

echo "== [CHECK] last 80 lines for VSP_API_HIT =="
sudo journalctl -u "$SVC" --since "30 seconds ago" --no-pager -o cat | grep '\[VSP_API_HIT\]' | tail -n 80 || true

echo "== [DONE] If you see VSP_API_HIT lines, run the top-endpoints aggregation next =="
