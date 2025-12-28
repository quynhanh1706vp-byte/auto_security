#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true

echo "== [1] restore gateway from known-good vsp5hang backup =="
BAK="$(ls -1t "${W}.bak_p3k26_vsp5hang_"* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] missing ${W}.bak_p3k26_vsp5hang_*"; exit 2; }
cp -f "$BAK" "$W"
echo "[OK] restored $W from $BAK"

echo "== [2] patch: hard WSGI HTML response for /vsp5 (no app call, no recursion) =="
python3 - <<'PY'
from pathlib import Path
import re

W=Path("wsgi_vsp_ui_gateway.py")
lines=W.read_text(encoding="utf-8", errors="replace").splitlines(True)

TAG="P3K26_VSP5_WSGI_HTML_SHELL_V14"
if any(TAG in ln for ln in lines):
    print("[OK] already patched (no-op)")
    raise SystemExit(0)

# find a wrapper def(environ, start_response)
wrap_idx=None
for i,ln in enumerate(lines):
    if ln.lstrip().startswith("def ") and ("environ" in ln and "start_response" in ln) and ln.rstrip().endswith(":"):
        wrap_idx=i
        break
if wrap_idx is None:
    raise SystemExit("[ERR] cannot find def(environ, start_response) in gateway")

def_indent = len(lines[wrap_idx]) - len(lines[wrap_idx].lstrip())
body_indent = def_indent + 4

# insert right after def (+ optional docstring)
ins = wrap_idx + 1
while ins < len(lines) and lines[ins].strip()=="":
    ins += 1
if ins < len(lines) and lines[ins].lstrip().startswith(('"""',"'''")):
    q = lines[ins].lstrip()[:3]
    ins += 1
    while ins < len(lines) and q not in lines[ins]:
        ins += 1
    if ins < len(lines):
        ins += 1

pad=" " * body_indent
html = (
    "<!doctype html><html><head><meta charset=\"utf-8\">"
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    "<title>VSP Dashboard</title>"
    "</head><body style=\"margin:0;background:#0b1220;color:#e5e7eb;\">"
    "<div id=\"vsp-dashboard-main\"></div>"
    "<script src=\"/static/js/vsp_bundle_tabs5_v1.js\"></script>"
    "</body></html>"
)
snippet = (
    f"{pad}# {TAG}: serve /vsp5 as pure WSGI HTML (bypass app & after_request)\n"
    f"{pad}try:\n"
    f"{pad}    if (environ.get('PATH_INFO') or '') == '/vsp5':\n"
    f"{pad}        _b = {html!r}.encode('utf-8')\n"
    f"{pad}        start_response('200 OK', [\n"
    f"{pad}            ('Content-Type','text/html; charset=utf-8'),\n"
    f"{pad}            ('Cache-Control','no-store'),\n"
    f"{pad}            ('Content-Length', str(len(_b))),\n"
    f"{pad}        ])\n"
    f"{pad}        return [_b]\n"
    f"{pad}except Exception:\n"
    f"{pad}    pass\n"
)

lines.insert(ins, snippet)
W.write_text("".join(lines), encoding="utf-8")
print(f"[OK] inserted hard /vsp5 WSGI shell at wrapper line {wrap_idx+1}")
PY

echo "== [3] py_compile gateway =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [4] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [5] smoke /vsp5 (3s) =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,90p'
echo "== head /tmp/vsp5.html =="
head -n 20 /tmp/vsp5.html || true
echo "[DONE] p3k26_gateway_hardfix_vsp5_wsgishell_v14"
