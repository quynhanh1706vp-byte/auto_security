#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs500fallback_v2_${TS}"
echo "[BACKUP] ${F}.bak_runs500fallback_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUNS_500_FALLBACK_MW_P0_V2"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

snippet = r'''
# === VSP_RUNS_500_FALLBACK_MW_P0_V2 ===
class VSPRuns500FallbackMWP0V2:
    def __init__(self, app):
        self.app = app

    def _fallback(self, start_response, why=""):
        html = (
            "<!doctype html><html><head><meta charset='utf-8'>"
            "<title>Runs & Reports (fallback)</title></head>"
            "<body style='font-family:ui-sans-serif,system-ui;max-width:980px;margin:18px auto;"
            "padding:0 14px;color:#ddd;background:#0b0f14;'>"
            "<h2 style='margin:0 0 8px 0;'>Runs & Reports</h2>"
            "<div style='opacity:.85;margin-bottom:14px;'>"
            "UI /runs đang lỗi (500). Đây là trang fallback (P0) để demo không sập.</div>"
            "<div style='display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px;'>"
            "<a href='/vsp4' style='color:#9ab;'>Dashboard</a>"
            "<a href='/data' style='color:#9ab;'>Data Source</a>"
            "<a href='/settings' style='color:#9ab;'>Settings</a>"
            "<a href='/rule_overrides' style='color:#9ab;'>Rule Overrides</a>"
            "</div>"
            "<div style='padding:12px;border:1px solid rgba(255,255,255,.1);border-radius:12px;"
            "background:rgba(255,255,255,.03);'>"
            "<div style='font-weight:800;margin-bottom:8px;'>Quick Links</div>"
            "<ul style='margin:0;padding-left:18px;line-height:1.7;'>"
            "<li><a href='/api/vsp/runs?limit=50' style='color:#9ab;'>/api/vsp/runs?limit=50</a></li>"
            "<li><a href='/api/vsp/selfcheck_p0' style='color:#9ab;'>/api/vsp/selfcheck_p0</a></li>"
            "<li><a href='/findings_unified.json' style='color:#9ab;'>/findings_unified.json</a></li>"
            "</ul>"
            "</div>"
            f"<pre style='opacity:.65;margin-top:14px;font-size:12px;white-space:pre-wrap;'>"
            f"Marker: {MARK}\n{why}</pre>"
            "</body></html>"
        ).encode("utf-8","replace")

        start_response("200 OK", [
            ("Content-Type","text/html; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("X-VSP-RUNS-FALLBACK", MARK),
            ("Content-Length", str(len(html))),
        ])
        return [html]

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path != "/runs":
            return self.app(environ, start_response)

        # CRITICAL: catch exception thrown before start_response (Flask route crash)
        try:
            meta = {}
            def sr(status, headers, exc_info=None):
                meta["status"]=status
                meta["headers"]=headers
                meta["exc_info"]=exc_info
                return lambda _x: None

            it = self.app(environ, sr)

            body=b""
            try:
                for c in it:
                    if c: body += c
            finally:
                try:
                    close=getattr(it,"close",None)
                    if callable(close): close()
                except Exception:
                    pass

            status = meta.get("status") or "200 OK"
            code = 0
            try: code = int(str(status).split()[0])
            except Exception: code = 0

            if code >= 500:
                return self._fallback(start_response, why=f"upstream_status={status}")

            # normal response
            hdrs = meta.get("headers") or []
            start_response(status, hdrs, meta.get("exc_info"))
            return [body]

        except Exception as e:
            return self._fallback(start_response, why=f"exception={type(e).__name__}: {e}")

try:
    if "application" in globals():
        _a = globals().get("application")
        if _a is not None and not getattr(_a, "__VSP_RUNS_500_FALLBACK_MW_P0_V2__", False):
            _mw = VSPRuns500FallbackMWP0V2(_a)
            setattr(_mw, "__VSP_RUNS_500_FALLBACK_MW_P0_V2__", True)
            globals()["application"] = _mw
except Exception:
    pass
# === /VSP_RUNS_500_FALLBACK_MW_P0_V2 ===
'''
p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "[NEXT] restart + verify GET /runs returns 200 fallback"
