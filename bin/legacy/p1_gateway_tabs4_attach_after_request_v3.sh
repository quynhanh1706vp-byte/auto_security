#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_tabs4_attach_v3_${TS}"
echo "[BACKUP] ${W}.bak_tabs4_attach_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_GATEWAY_TABS4_ATTACH_AFTER_REQUEST_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_GATEWAY_TABS4_ATTACH_AFTER_REQUEST_V3 =====================
def _vsp_tabs4_inject_autorid_after_request(resp):
    # Attach-safe: import inside to avoid early import/order issues
    try:
        import time, re
        from flask import request
    except Exception:
        return resp

    try:
        p = (request.path or "").rstrip("/") or "/"
    except Exception:
        return resp

    # never touch dashboard
    if p.startswith("/vsp5"):
        return resp

    # only 4 tabs (exclude /reports because it's JSON in your setup)
    targets = {"/runs", "/runs_reports", "/settings", "/data_source", "/rule_overrides"}
    if p not in targets:
        return resp

    try:
        ct = (resp.headers.get("Content-Type") or "").lower()
    except Exception:
        ct = ""
    if "text/html" not in ct:
        return resp

    try:
        body = resp.get_data(as_text=True)
    except Exception:
        return resp

    v = str(int(time.time()))

    # sanitize any broken src fragments that might appear
    try:
        body = re.sub(r"vsp_tabs4_autorid_v1\.js\?v=\{\{[^\}]*\}\}", "vsp_tabs4_autorid_v1.js?v="+v, body)
        body = re.sub(r"vsp_tabs4_autorid_v1\.js\?v=\{[^\\"'\s>]*", "vsp_tabs4_autorid_v1.js?v="+v, body)
    except Exception:
        pass

    tag = f'\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={v}"></script>\n'

    if "vsp_tabs4_autorid_v1.js" in body:
        # keep sanitation
        try:
            resp.set_data(body)
            resp.headers.pop("Content-Length", None)
            resp.headers["Cache-Control"] = "no-store"
            resp.headers["X-VSP-AUTORID-INJECT"] = "1"
        except Exception:
            return resp
        return resp

    # inject robustly: </head> -> </body> -> append
    if "</head>" in body:
        body = body.replace("</head>", tag + "</head>", 1)
    elif "</body>" in body:
        body = body.replace("</body>", tag + "</body>", 1)
    else:
        body = body + tag

    try:
        resp.set_data(body)
        resp.headers.pop("Content-Length", None)
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["X-VSP-AUTORID-INJECT"] = "1"
    except Exception:
        return resp
    return resp

# Attach to real Flask app objects if they exist (both names supported)
try:
    _a1 = globals().get("app")
    if _a1 and hasattr(_a1, "after_request"):
        _a1.after_request(_vsp_tabs4_inject_autorid_after_request)
except Exception:
    pass
try:
    _a2 = globals().get("application")
    if _a2 and hasattr(_a2, "after_request"):
        _a2.after_request(_vsp_tabs4_inject_autorid_after_request)
except Exception:
    pass
# ===================== /VSP_P1_GATEWAY_TABS4_ATTACH_AFTER_REQUEST_V3 =====================
""").strip() + "\n"

# Insert right after "app = application" if present; else append to end.
m = re.search(r'^\s*app\s*=\s*application\s*$', s, re.M)
if m:
    pos = m.end()
    s2 = s[:pos] + "\n\n" + block + "\n" + s[pos:]
else:
    s2 = s.rstrip() + "\n\n" + block

W.write_text(s2, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + compiled:", MARK)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify (must show src + header) =="
for p in /runs /runs_reports /settings /data_source /rule_overrides; do
  echo "-- $p --"
  curl -sS -I "$BASE$p" | grep -i "X-VSP-AUTORID-INJECT" || true
  curl -sS "$BASE$p" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 2 || true
done
