#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_artopen_fixct_${TS}"
echo "[BACKUP] $F.bak_artopen_fixct_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Replace only the function body if present; else append a new installer (safe).
if "api_vsp_run_artifact_open_v1" not in t:
    print("[ERR] artifact_open_v1 not found in wsgi, install it first")
    raise SystemExit(2)

TAG = "VSP_GATEWAY_ARTIFACT_OPEN_V2_FIXCT"
if TAG in t:
    print("[OK] already fixed, skip")
    raise SystemExit(0)

# Patch: inside api_vsp_run_artifact_open_v1, replace the send_file/HEAD part with Response-based
pat = r"@_app\.route\(\"/api/vsp/run_artifact_open_v1/<rid>\"[\s\S]*?def api_vsp_run_artifact_open_v1\(rid\):([\s\S]*?)return send_file"
m = re.search(pat, t)
if not m:
    print("[ERR] cannot locate artifact_open handler block to patch")
    raise SystemExit(3)

# We'll do a more surgical replace: find from "ctype =" to end of function and replace that tail.
pat2 = r"(ctype\s*=\s*mimetypes\.guess_type\(str\(f\)\)\[0\][\s\S]*?\n\s*return send_file[\s\S]*?\n)"
m2 = re.search(pat2, t)
if not m2:
    print("[ERR] cannot locate tail to replace")
    raise SystemExit(4)

tail = r'''
        ctype = mimetypes.guess_type(str(f))[0] or "application/octet-stream"

        # meta mode for quick debugging
        if request.args.get("meta","0") == "1":
            return jsonify(ok=True, rid=rid, rel=rel, abs=str(f), ctype=ctype, size=int(f.stat().st_size)), 200

        if request.method == "HEAD":
            resp = Response(status=200)
            resp.headers["Content-Type"] = ctype
            resp.headers["X-VSP-ARTOPEN"] = "ok"
            try:
                resp.headers["Content-Length"] = str(f.stat().st_size)
            except Exception:
                pass
            return resp

        # Read file and respond with explicit mimetype (resists gateway header overrides better than send_file)
        data = f.read_bytes()
        resp = Response(data, status=200, mimetype=ctype)
        resp.headers["X-VSP-ARTOPEN"] = "ok"
        resp.headers["X-Content-Type-Options"] = "nosniff"
        return resp
'''
t2 = t[:m2.start(1)] + tail + t[m2.end(1):]

t2 += "\n# === %s ===\n" % TAG
p.write_text(t2, encoding="utf-8")
print("[OK] patched artifact_open to Response(mimetype=...) + meta=1")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"

echo "[DONE] restart 8910 (no sudo)"
bin/restart_8910_nosudo_force_v1.sh
