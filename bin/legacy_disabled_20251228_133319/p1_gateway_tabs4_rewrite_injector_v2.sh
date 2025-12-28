#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TPL_DIR="templates"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_rewrite_${TS}"
echo "[SNAPSHOT] ${W}.bak_before_rewrite_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re, textwrap

W = Path("wsgi_vsp_ui_gateway.py")

def compiles(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

# 1) Restore latest compiling backup (if current broken)
if not compiles(W):
    baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
    good = None
    for p in baks:
        if compiles(p):
            good = p
            break
    if good is None:
        raise SystemExit("[FATAL] No compiling backup found for wsgi_vsp_ui_gateway.py")
    W.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[OK] restored from compiling backup:", good.name)
else:
    print("[OK] current gateway already compiles")

s = W.read_text(encoding="utf-8", errors="replace")

START = "# ===================== VSP_P1_GATEWAY_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1 ====================="
END   = "# ===================== /VSP_P1_GATEWAY_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1 ====================="
if START not in s or END not in s:
    raise SystemExit("[FATAL] cannot find injector block markers in gateway (START/END missing).")

# 2) Rewrite whole block content between START..END with a clean implementation (compile-safe)
new_block = textwrap.dedent(rf"""
{START}
# NOTE: rewritten V2 (compile-safe). Inject autorid ONLY for 4 tabs, never dashboard, never /reports (json).
import re as _vsp_re
import time as _vsp_time
try:
    from flask import request as _vsp_request
except Exception:
    _vsp_request = None

def _vsp_gateway_asset_v():
    # stable-ish per request, ok for cache-bust
    try:
        v = str(globals().get("_VSP_ASSET_V", "") or "")
        if v and v.isdigit():
            return v
    except Exception:
        pass
    try:
        return str(int(_vsp_time.time()))
    except Exception:
        return "1"

def _vsp_gateway_get_app():
    try:
        return globals().get("app") or globals().get("application")
    except Exception:
        return None

_VSP_GATEWAY_APP = _vsp_gateway_get_app()

if _VSP_GATEWAY_APP and _vsp_request:
    @_VSP_GATEWAY_APP.after_request
    def _vsp_gateway_after_request_tabs4_inject_autorid(resp):
        try:
            p = (_vsp_request.path or "").rstrip("/") or "/"
        except Exception:
            return resp

        # NEVER touch dashboard
        if p.startswith("/vsp5"):
            return resp

        # ONLY 4 tabs
        targets = {{"/runs", "/runs_reports", "/settings", "/data_source", "/rule_overrides"}}
        if p not in targets:
            return resp

        # only HTML
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

        v = _vsp_gateway_asset_v()

        # sanitize any broken src like ?v={ asset_v|default(...) } that might still exist in HTML
        try:
            body = _vsp_re.sub(r"vsp_tabs4_autorid_v1\.js\?v=\{{[^}}]*\}}", f"vsp_tabs4_autorid_v1.js?v={{v}}", body)
            body = _vsp_re.sub(r"vsp_tabs4_autorid_v1\.js\?v=\{{[^}}]*", f"vsp_tabs4_autorid_v1.js?v={{v}}", body)
        except Exception:
            pass

        # If already present, still re-set body (in case we sanitized)
        if "vsp_tabs4_autorid_v1.js" in body:
            try:
                resp.set_data(body)
                resp.headers.pop("Content-Length", None)
                resp.headers["Cache-Control"] = "no-store"
            except Exception:
                return resp
            return resp

        tag = f'\\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={{v}}"></script>\\n'
        if "</body>" in body:
            body = body.replace("</body>", tag + "</body>", 1)
        else:
            body = body + tag

        try:
            resp.set_data(body)
            resp.headers.pop("Content-Length", None)
            resp.headers["Cache-Control"] = "no-store"
        except Exception:
            return resp
        return resp
{END}
""").strip() + "\n"

pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
s2, n = pattern.subn(new_block, s)
if n != 1:
    raise SystemExit(f"[FATAL] rewrite block failed, replacements={n}")

W.write_text(s2, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] gateway injector rewritten cleanly (V2) + compiles")

# 3) Clean templates: remove old Jinja-based autorid script tags to avoid showing '?v={{...}}' fragments
tpl_dir = Path("templates")
pat = re.compile(
    r'<!--\s*VSP_P1_TABS4_AUTORID_NODASH_V1\s*-->\s*<script[^>]*vsp_tabs4_autorid_v1\.js\?v=\{\{.*?\}\}[^>]*></script>\s*',
    re.I | re.S
)
cleaned = 0
for p in tpl_dir.rglob("*.html"):
    t = p.read_text(encoding="utf-8", errors="replace")
    t2, k = pat.subn("", t)
    if k:
        p.write_text(t2, encoding="utf-8")
        cleaned += k
        print("[OK] cleaned template:", p.name, "count=", k)
print("[INFO] total template clean blocks:", cleaned)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify autorid src in /runs (must be numeric v, no braces) =="
curl -sS "$BASE/runs" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 3 || true
echo "== verify autorid src in /settings =="
curl -sS "$BASE/settings" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 3 || true
