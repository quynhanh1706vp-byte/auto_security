#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$APP.bak_json_err_${TS}"
echo "[BACKUP] $APP.bak_json_err_${TS}"

python3 - << 'PY'
from pathlib import Path
import re, time

app = Path("vsp_demo_app.py")
txt = app.read_text(encoding="utf-8", errors="ignore")

if "VSP_JSON_ERRHANDLERS_V1" in txt:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Ensure jsonify import exists
if "from flask import jsonify" not in txt and "import jsonify" not in txt:
    # Try add to existing "from flask import ..."
    m = re.search(r"from\s+flask\s+import\s+([^\n]+)\n", txt)
    if m:
        line = m.group(0)
        if "jsonify" not in line:
            newline = line.rstrip("\n")
            if newline.endswith(")"):
                # very rare
                pass
            else:
                newline = newline + ", jsonify\n"
            txt = txt.replace(line, newline, 1)
    else:
        txt = "from flask import jsonify\n" + txt

patch = r"""
# === VSP_JSON_ERRHANDLERS_V1 ===
# Guarantee /api/vsp/* never breaks jq: 404/500 -> JSON
try:
    import vsp_status_contract_v1 as vsp_sc
except Exception:
    vsp_sc = None

def _vsp_json_err_payload(code: int, msg: str):
    base = {"ok": False, "status": "ERROR", "final": True, "error": msg, "http_code": code}
    if vsp_sc:
        try:
            base = vsp_sc.normalize_run_status_payload(base)
        except Exception:
            pass
    return base

@app.errorhandler(404)
def _vsp_err_404(e):
    # only JSON for api paths; keep normal HTML for UI pages
    try:
        path = getattr(e, "description", "") or ""
    except Exception:
        path = ""
    # Flask doesn't always provide path here; use request.path if available
    try:
        from flask import request, jsonify
        if request.path.startswith("/api/vsp/"):
            return jsonify(_vsp_json_err_payload(404, "HTTP_404_NOT_FOUND")), 200
    except Exception:
        pass
    return e, 404

@app.errorhandler(500)
def _vsp_err_500(e):
    try:
        from flask import request, jsonify
        if request.path.startswith("/api/vsp/"):
            return jsonify(_vsp_json_err_payload(500, "HTTP_500_INTERNAL")), 200
    except Exception:
        pass
    return e, 500
# === END VSP_JSON_ERRHANDLERS_V1 ===
"""

# Insert patch near app initialization end: after "app = Flask(" if possible
anchor = re.search(r"^\s*app\s*=\s*Flask\(", txt, flags=re.M)
if anchor:
    # insert after the line containing app = Flask(...)
    lines = txt.splitlines(True)
    idx = 0
    for i, ln in enumerate(lines):
        if re.search(r"^\s*app\s*=\s*Flask\(", ln):
            idx = i + 1
            break
    lines.insert(idx, patch + "\n")
    txt2 = "".join(lines)
else:
    txt2 = txt + "\n" + patch + "\n"

app.write_text(txt2, encoding="utf-8")
print("[OK] patched vsp_demo_app.py with JSON errorhandlers")
PY

echo "[OK] patch done"
