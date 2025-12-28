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
cp -f "$APP" "${APP}.bak_jsnorm_${TS}"
echo "[BACKUP] ${APP}.bak_jsnorm_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_STATIC_JS_NORMALIZE_V1D"
if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_STATIC_JS_NORMALIZE_V1D =====================
# Normalize broken /static/js URLs (trailing backslash, %22, quotes) and always serve JS with correct MIME.

from urllib.parse import unquote

@app.get("/static/js/<path:fname>")
def vsp_static_js_force_mime_normalize(fname):
    # fname may include encoded junk; normalize hard
    try:
        fname = unquote(fname)
    except Exception:
        pass
    fname = fname.strip().strip('"').strip("'")
    # strip a trailing backslash that often appears in templates
    while fname.endswith("\\"):
        fname = fname[:-1]
    # remove accidental leading %22 artifacts in path segments
    fname = fname.replace("%22", "").replace("\\\"", "")
    # security: block traversal
    if not fname or ".." in fname or fname.startswith(("/", "\\")):
        abort(404)

    root = _Path(__file__).resolve().parent
    jsdir = root / "static" / "js"
    fpath = jsdir / fname
    if not fpath.is_file():
        abort(404)

    return send_from_directory(str(jsdir), fname, mimetype="application/javascript")
# ===================== /VSP_P1_STATIC_JS_NORMALIZE_V1D =====================
""").strip() + "\n"

m = re.search(r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s2 = s[:m.start()] + "\n\n" + block + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted static js normalize block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [VERIFY] try common broken variants =="
curl -fsS -I "$BASE/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,8p'
curl -fsS -I "$BASE/static/js/vsp_data_source_lazy_v1.js%5C" | sed -n '1,8p' || true
