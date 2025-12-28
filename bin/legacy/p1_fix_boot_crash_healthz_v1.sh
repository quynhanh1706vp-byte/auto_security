#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sudo; need systemctl; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"

# --- A) comment-out any @app.get("/healthz") / @app.route("/healthz") lines in vsp_demo_app.py
F1="vsp_demo_app.py"
if [ -f "$F1" ]; then
  cp -f "$F1" "${F1}.bak_fix_boot_${TS}"
  echo "[BACKUP] ${F1}.bak_fix_boot_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace").splitlines(True)

out=[]
changed=0
for line in s:
    # comment out any decorator that references app for /healthz
    if re.search(r'^\s*@app\.(get|route)\(\s*[\'"]\/healthz[\'"]', line):
        out.append("# " + line)   # comment to avoid NameError at import-time
        changed += 1
    else:
        out.append(line)

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] vsp_demo_app.py: commented {changed} healthz decorator line(s)")
PY

  python3 -m py_compile "$F1" && echo "[OK] py_compile OK: $F1"
else
  echo "[WARN] missing $F1 (skip)"
fi

# --- B) add strict /healthz at WSGI layer in wsgi_vsp_ui_gateway.py (safe, no Flask dependency)
F2="wsgi_vsp_ui_gateway.py"
[ -f "$F2" ] || { echo "[ERR] missing $F2"; exit 2; }

if ! grep -q "VSP_P1_HEALTHZ_WSGI_STRICT_V4" "$F2"; then
  cp -f "$F2" "${F2}.bak_healthz_wsgi_${TS}"
  echo "[BACKUP] ${F2}.bak_healthz_wsgi_${TS}"

  python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

block = r'''

# --- VSP_P1_HEALTHZ_WSGI_STRICT_V4 ---
# Guarantee JSON response even if Flask routes/templates change.
def _vsp_healthz_wsgi_wrap(_next):
    import json, os, time, socket
    def _app(environ, start_response):
        try:
            if environ.get("PATH_INFO") == "/healthz":
                payload = json.dumps({
                    "ui_up": True,
                    "ts": int(time.time()),
                    "pid": os.getpid(),
                    "host": socket.gethostname(),
                    "contract": "P1_HEALTHZ_V4"
                }).encode("utf-8")
                start_response("200 OK", [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Length", str(len(payload))),
                ])
                return [payload]
        except Exception:
            pass
        return _next(environ, start_response)
    return _app

try:
    # gunicorn entrypoint in this module is typically `application`
    if "application" in globals() and callable(application):
        application = _vsp_healthz_wsgi_wrap(application)
except Exception:
    pass
# --- /VSP_P1_HEALTHZ_WSGI_STRICT_V4 ---

'''
p.write_text(s + block, encoding="utf-8")
print("[OK] appended WSGI /healthz wrapper into", p)
PY

  python3 -m py_compile "$F2" && echo "[OK] py_compile OK: $F2"
else
  echo "[OK] already has V4 in $F2"
fi

echo "== restart service =="
sudo systemctl restart vsp-ui-8910.service || true
sudo systemctl status vsp-ui-8910.service --no-pager | sed -n '1,30p' || true

echo "== probes =="
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p' || true
curl -sS -i http://127.0.0.1:8910/healthz | sed -n '1,25p' || true
