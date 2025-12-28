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
cp -f "$W" "${W}.bak_tabs4_inject_${TS}"
echo "[BACKUP] ${W}.bak_tabs4_inject_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_GATEWAY_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_GATEWAY_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1 =====================
try:
    import time as _vsp_time
except Exception:
    _vsp_time = None

try:
    from flask import request
except Exception:
    request = None

def _vsp_gateway_asset_v():
    # best effort: use existing asset_v if gateway has it, else timestamp
    try:
        v = str(globals().get("_VSP_ASSET_V", "") or "")
        if v:
            return v
    except Exception:
        pass
    try:
        return str(int(_vsp_time.time())) if _vsp_time else "1"
    except Exception:
        return "1"

def _vsp_gateway_get_app():
    try:
        return globals().get("app") or globals().get("application")
    except Exception:
        return None

_VSP_GATEWAY_APP = _vsp_gateway_get_app()

if _VSP_GATEWAY_APP and request:
    @_VSP_GATEWAY_APP.after_request
    def _vsp_gateway_after_request_tabs4_inject_autorid(resp):
        try:
            p = (request.path or "").rstrip("/") or "/"
        except Exception:
            return resp

        # DO NOT touch dashboard
        if p.startswith("/vsp5"):
            return resp

        # only 4 tabs + optional reports if HTML
        targets = {"/runs", "/runs_reports", "/settings", "/data_source", "/rule_overrides", "/reports"}
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

        if "vsp_tabs4_autorid_v1.js" in body:
            return resp

        v = _vsp_gateway_asset_v()
        tag = f'\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={v}"></script>\n'
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
# ===================== /VSP_P1_GATEWAY_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1 =====================
""").strip() + "\n"

s2 = s.rstrip() + "\n\n" + block
W.write_text(s2, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched gateway:", MARK)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: autorid present in HTML? =="
for p in /runs /runs_reports /settings /data_source /rule_overrides /reports; do
  echo "-- $p --"
  if curl -sS "$BASE$p" | grep -q "vsp_tabs4_autorid_v1.js"; then
    echo "[OK] autorid injected"
  else
    echo "[WARN] no autorid (maybe not HTML route)"
  fi
done

echo "== smoke: list js tags (runs) =="
curl -sS "$BASE/runs" | grep -oE '/static/js/[^"]+\.js\?v=[0-9]+' | head -n 20
