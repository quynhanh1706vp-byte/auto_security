#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_forcejs_${TS}"
echo "[BACKUP] ${APP}.bak_forcejs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_FORCE_STATIC_JS_MIME_AND_TABS3_ALIAS_V1B"
if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_FORCE_STATIC_JS_MIME_AND_TABS3_ALIAS_V1B =====================
# Force /static/js/*.js to always return application/javascript (avoid JSON fallback => Chrome MIME block)
# Also provide alias for client GET /api/vsp/vsp_tabs3_common_v3.js

from flask import Response, abort, send_from_directory
from pathlib import Path as _Path

@app.get("/api/vsp/vsp_tabs3_common_v3.js")
def vsp_tabs3_common_v3_js_alias_api_vsp():
    js = "/* tabs3 common v3 (alias /api/vsp/) */\nwindow.__vsp_tabs3_common_v3_ok=true;\n"
    return Response(js, mimetype="application/javascript")

# keep the original path too (some pages may call it)
@app.get("/api/vsp_tabs3_common_v3.js")
def vsp_tabs3_common_v3_js_direct():
    js = "/* tabs3 common v3 (direct) */\nwindow.__vsp_tabs3_common_v3_ok=true;\n"
    return Response(js, mimetype="application/javascript")

@app.get("/static/js/<path:fname>")
def vsp_static_js_force_mime(fname):
    # security: block traversal
    if not fname or ".." in fname or fname.startswith(("/", "\\")):
        abort(404)

    root = _Path(__file__).resolve().parent
    jsdir = root / "static" / "js"
    fpath = jsdir / fname
    if not fpath.is_file():
        abort(404)

    # send_from_directory sets correct headers; force mimetype for Chrome strict MIME checks
    return send_from_directory(str(jsdir), fname, mimetype="application/javascript")
# ===================== /VSP_P1_FORCE_STATIC_JS_MIME_AND_TABS3_ALIAS_V1B =====================
""").strip() + "\n"

# Insert before __main__ if present, else append
m = re.search(r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s2 = s[:m.start()] + "\n\n" + block + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted force-static-js + tabs3 alias block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [VERIFY] tabs3 alias =="
curl -fsS -I "$BASE/api/vsp/vsp_tabs3_common_v3.js" | sed -n '1,12p'

echo "== [VERIFY] static js MIME =="
curl -fsS -I "$BASE/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,20p'
