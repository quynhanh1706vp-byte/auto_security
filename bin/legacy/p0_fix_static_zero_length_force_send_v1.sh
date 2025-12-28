#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_static_${TS}"
echo "[BACKUP] ${F}.bak_fix_static_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_STATIC_FORCE_SEND_V1"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

# We will inject:
#  - import send_from_directory
#  - a route /static/<path:filename> that serves from ./static with cache_control no-cache
# This must be registered after app creation (app = Flask(...)).
# We'll try to inject right after app = Flask(...) block.
imp_pat = r'from\s+flask\s+import\s+([^\n]+)'
if "send_from_directory" not in s:
    # add send_from_directory into the first "from flask import ..." line
    def add_send(m):
        parts = m.group(1)
        if "send_from_directory" in parts:
            return m.group(0)
        return "from flask import " + parts.rstrip() + ", send_from_directory"
    s2, n = re.subn(imp_pat, add_send, s, count=1, flags=re.M)
    s = s2

inject = f"""
# === {marker} ===
# Commercial: force-serve static assets from disk (fix 200-but-empty body issues)
try:
    import os
    from flask import Response
except Exception:
    pass

@app.get("/static/<path:filename>")
def vsp_p0_static_force_send_v1(filename):
    try:
        root = os.path.join(os.path.dirname(__file__), "static")
        resp = send_from_directory(root, filename)
        # ensure not cached in dev; commercial can tune later
        resp.headers["Cache-Control"] = "no-cache"
        return resp
    except Exception as e:
        # explicit non-empty error
        return Response("static serve error: " + str(e), status=500, mimetype="text/plain")
# === END {marker} ===
"""

# Find app creation line
m = re.search(r'^\s*app\s*=\s*Flask\([^\n]*\)\s*$', s, flags=re.M)
if not m:
    # fallback: append near end
    s = s + "\n" + inject + "\n"
    print("[WARN] app=Flask(...) not found; appended patch at end")
else:
    pos = m.end()
    s = s[:pos] + "\n" + inject + s[pos:]
    print("[OK] injected patch after app creation")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY

# sanity compile
python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "[DONE] static force-send patch applied."
