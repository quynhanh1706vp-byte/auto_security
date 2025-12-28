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
cp -f "$APP" "${APP}.bak_qdecode_${TS}"
echo "[BACKUP] ${APP}.bak_qdecode_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DECODED_QUOTE_STATIC_REDIRECT_V1G"
if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_DECODED_QUOTE_STATIC_REDIRECT_V1G =====================
# Flask matches routes on DECODED path.
# /%22/static/... becomes /"/static/...
# Also some templates may accidentally append a trailing backslash: ...js%5C -> decoded ...js\

from flask import redirect, request

def _vsp__redir(url_base: str, rest: str):
    qs = request.query_string.decode("utf-8", errors="ignore")
    url = url_base + rest
    if qs:
        url = url + "?" + qs
    return redirect(url, code=307)

# 1) decoded leading quote case: /"/static/...
@app.get('/"/static/<path:rest>')
def vsp_decoded_quote_static_redirect(rest):
    return _vsp__redir("/static/", rest)

# 2) decoded leading backslash case: /\static/...  (rare but seen)
@app.get('/\\static/<path:rest>')
def vsp_decoded_backslash_static_redirect(rest):
    return _vsp__redir("/static/", rest)

# 3) trailing backslash after .js: /static/js/x.js\  (decoded from %5C)
@app.get('/static/js/<path:rest>\\')
def vsp_static_js_trailing_backslash_redirect(rest):
    return _vsp__redir("/static/js/", rest)

# 4) trailing backslash after .css (optional safety)
@app.get('/static/css/<path:rest>\\')
def vsp_static_css_trailing_backslash_redirect(rest):
    return _vsp__redir("/static/css/", rest)

# ===================== /VSP_P1_DECODED_QUOTE_STATIC_REDIRECT_V1G =====================
""").strip() + "\n"

m = re.search(r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s2 = s[:m.start()] + "\n\n" + block + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted v1g decoded-quote/trailing-backslash redirect routes")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [VERIFY] /%22/static should now be 307 then JS =="
curl -fsS -I "$BASE/%22/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,15p'
curl -fsS -L -I "$BASE/%22/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,15p'

echo "== [VERIFY] trailing backslash js (encoded) should 307 then JS =="
curl -fsS -I "$BASE/static/js/vsp_data_source_lazy_v1.js%5C" | sed -n '1,15p'
curl -fsS -L -I "$BASE/static/js/vsp_data_source_lazy_v1.js%5C" | sed -n '1,15p'
