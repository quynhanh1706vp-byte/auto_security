#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_api_json_guard_bp_dedupe_${TS}"
echo "[BACKUP] $F.bak_api_json_guard_bp_dedupe_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

# 0) ensure imports for jsonify + request + HTTPException
# add jsonify into existing "from flask import ..."
if "from flask import" in txt:
    m = re.search(r"^from flask import ([^\n]+)$", txt, flags=re.M)
    if m:
        imports = [s.strip() for s in m.group(1).split(",")]
        changed = False
        for need in ["jsonify", "request"]:
            if need not in imports:
                imports.append(need); changed = True
        if changed:
            new_line = "from flask import " + ", ".join(imports)
            txt = txt[:m.start()] + new_line + txt[m.end():]
else:
    # fallback: prepend minimal imports
    txt = "from flask import jsonify, request\n" + txt

if "from werkzeug.exceptions import HTTPException" not in txt:
    # insert near top after flask imports
    m2 = re.search(r"^from flask import [^\n]+\n", txt, flags=re.M)
    ins_at = m2.end() if m2 else 0
    txt = txt[:ins_at] + "from werkzeug.exceptions import HTTPException\n" + txt[ins_at:]

# 1) dedupe: wrap app.register_blueprint(bp_vsp_run_api_v1) lines
def repl_register(m):
    ind = m.group(1)
    return (
        f"{ind}if not getattr(app, '_VSP_BP_RUN_API_V1_REGISTERED', False):\n"
        f"{ind}    app.register_blueprint(bp_vsp_run_api_v1)\n"
        f"{ind}    app._VSP_BP_RUN_API_V1_REGISTERED = True\n"
        f"{ind}else:\n"
        f"{ind}    print('[VSP_RUN_API] skip duplicate blueprint register: vsp_run_api_v1')\n"
    )

txt2 = re.sub(r"^(\s*)app\.register_blueprint\(\s*bp_vsp_run_api_v1\s*\)\s*$", repl_register, txt, flags=re.M)
txt = txt2

# 2) add API JSON errorhandler (do NOT break normal pages)
marker = "# === VSP_API_JSON_ERROR_GUARD_V1 ==="
if marker not in txt:
    block = f"""
{marker}
@app.errorhandler(Exception)
def vsp_api_json_error_guard_v1(e):
    # Keep HTTPException behavior
    if isinstance(e, HTTPException):
        return e
    try:
        path = request.path or ""
    except Exception:
        path = ""
    # For APIs: always return JSON (commercial)
    if path.startswith("/api/"):
        return jsonify({{"ok": False, "error": str(e), "path": path}}), 500
    # Non-API: fallback to default plain text 500
    return "Internal Server Error", 500
# === END VSP_API_JSON_ERROR_GUARD_V1 ===
"""
    # insert before main if possible, else append
    m3 = re.search(r"^if __name__\s*==\s*['\"]__main__['\"]\s*:\s*$", txt, flags=re.M)
    if m3:
        txt = txt[:m3.start()] + block + "\n" + txt[m3.start():]
    else:
        txt = txt + "\n" + block
else:
    print("[INFO] API JSON guard already present; skip")

p.write_text(txt, encoding="utf-8")
print("[OK] wrote", p)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py OK"
echo "[DONE] patched: api json error guard + bp dedupe"
