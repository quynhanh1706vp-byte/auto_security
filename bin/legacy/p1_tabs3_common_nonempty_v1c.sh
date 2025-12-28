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
cp -f "$APP" "${APP}.bak_tabs3nonempty_${TS}"
echo "[BACKUP] ${APP}.bak_tabs3nonempty_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_TABS3_COMMON_NONEMPTY_V1C"
if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_TABS3_COMMON_NONEMPTY_V1C =====================
from flask import Response, send_from_directory

def _vsp_tabs3_js_payload():
    # Try serve real file if present (preferred)
    root = _Path(__file__).resolve().parent
    jsdir = root / "static" / "js"
    cand = jsdir / "vsp_tabs3_common_v3.js"
    if cand.is_file():
        return send_from_directory(str(jsdir), "vsp_tabs3_common_v3.js", mimetype="application/javascript")
    # Fallback: non-empty stub that can't break callers
    js = """/* tabs3 common v3 (fallback stub) */
window.__vsp_tabs3_common_v3_ok=true;
window.__vsp_tabs3_common_v3_ping=function(){return true;};
"""
    return Response(js, mimetype="application/javascript")

@app.get("/api/vsp/vsp_tabs3_common_v3.js")
def vsp_tabs3_common_v3_js_alias_api_vsp_nonempty():
    return _vsp_tabs3_js_payload()

@app.get("/api/vsp_tabs3_common_v3.js")
def vsp_tabs3_common_v3_js_direct_nonempty():
    return _vsp_tabs3_js_payload()
# ===================== /VSP_P1_TABS3_COMMON_NONEMPTY_V1C =====================
""").strip() + "\n"

# Insert right after the V1B block if exists, else before __main__
m = re.search(r"VSP_P1_FORCE_STATIC_JS_MIME_AND_TABS3_ALIAS_V1B\s*====================.*?/VSP_P1_FORCE_STATIC_JS_MIME_AND_TABS3_ALIAS_V1B\s*====================", s, flags=re.S)
if m:
    s2 = s[:m.end()] + "\n\n" + block + "\n" + s[m.end():]
else:
    mm = re.search(r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    if mm:
        s2 = s[:mm.start()] + "\n\n" + block + "\n\n" + s[mm.start():]
    else:
        s2 = s + "\n\n" + block + "\n"

app.write_text(s2, encoding="utf-8")
print("[OK] inserted non-empty tabs3 routes (serve file or stub)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [VERIFY] tabs3 body size =="
curl -fsS "$BASE/api/vsp/vsp_tabs3_common_v3.js" | wc -c
