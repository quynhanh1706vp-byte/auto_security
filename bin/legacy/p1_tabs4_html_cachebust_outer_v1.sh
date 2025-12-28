#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK="${F}.bak_tabs4_htmlcb_${TS}"
cp -f "$F" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_TABS4_HTML_CACHEBUST_OUTER_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = textwrap.dedent(r'''
# ===================== VSP_P1_TABS4_HTML_CACHEBUST_OUTER_V1 =====================
# Outer wrapper: for 4 tabs HTML, rewrite ALL /static/js/*.js src to include v=<asset_v>
import re as _vsp__re

_vsp__inner_app_tabs4 = application

def _vsp__guess_asset_v(environ):
    # try global asset_v; fallback to env or hardcoded "1"
    av = globals().get("asset_v", None)
    if av is None:
        av = globals().get("ASSET_V", None)
    if av is None:
        av = environ.get("HTTP_X_VSP_ASSET_V", None)
    av = str(av or "").strip()
    return av or "1"

def _vsp__cachebust_url_keep_other_params(url: str, asset_v: str) -> str:
    if not url or not asset_v:
        return url
    av = str(asset_v).strip()
    if not av:
        return url
    frag = ""
    if "#" in url:
        url, frag0 = url.split("#", 1)
        frag = "#" + frag0
    if "?" in url:
        base, qs = url.split("?", 1)
        parts = [q for q in qs.split("&") if q and not q.strip().startswith("v=")]
        parts.append("v=" + av)
        return base + "?" + "&".join(parts) + frag
    return url + "?v=" + av + frag

def _vsp__cachebust_all_static_js_v2(html: str, asset_v: str) -> str:
    if not html or not asset_v:
        return html
    av = str(asset_v).strip()
    if not av:
        return html

    def repl_dq(m):
        url = m.group(1)
        if not url.startswith("/static/js/"):
            return m.group(0)
        fixed = _vsp__cachebust_url_keep_other_params(url, av)
        return f'src="{fixed}"'

    def repl_sq(m):
        url = m.group(1)
        if not url.startswith("/static/js/"):
            return m.group(0)
        fixed = _vsp__cachebust_url_keep_other_params(url, av)
        return f"src='{fixed}'"

    # IMPORTANT: allow spaces inside src value (e.g., v={{ asset_v }})
    html = _vsp__re.sub(r'src="([^"]+)"', repl_dq, html)
    html = _vsp__re.sub(r"src='([^']+)'", repl_sq, html)
    return html

def _vsp__tabs4_html_cachebust_wrapper(environ, start_response):
    path = environ.get("PATH_INFO","") or ""
    if path not in ("/runs","/settings","/data_source","/rule_overrides","/vsp5"):
        return _vsp__inner_app_tabs4(environ, start_response)

    cap = {}
    def _sr(status, headers, exc_info=None):
        cap["status"] = status
        cap["headers"] = headers or []
        cap["exc_info"] = exc_info
        def _write(_data): return None
        return _write

    it = _vsp__inner_app_tabs4(environ, _sr)
    try:
        body = b"".join(it) if it is not None else b""
    finally:
        try:
            close = getattr(it, "close", None)
            if callable(close): close()
        except Exception:
            pass

    status = cap.get("status","200 OK")
    headers = cap.get("headers",[]) or []
    ct = ""
    for k,v in headers:
        if str(k).lower()=="content-type":
            ct = str(v); break

    # only rewrite HTML
    if "text/html" not in (ct or "").lower():
        # normalize Content-Length
        nh = [(k,v) for (k,v) in headers if str(k).lower()!="content-length"]
        nh.append(("Content-Length", str(len(body))))
        start_response(status, nh, cap.get("exc_info"))
        return [body]

    av = _vsp__guess_asset_v(environ)
    html = body.decode("utf-8", errors="replace")
    html = _vsp__cachebust_all_static_js_v2(html, av)
    out = html.encode("utf-8")

    # keep headers but fix Content-Length; keep Content-Type as text/html
    nh = []
    have_ct = False
    for k,v in headers:
        lk = str(k).lower()
        if lk == "content-length":
            continue
        if lk == "content-type":
            have_ct = True
            nh.append(("Content-Type", "text/html; charset=utf-8"))
            continue
        nh.append((k,v))
    if not have_ct:
        nh.append(("Content-Type","text/html; charset=utf-8"))
    nh.append(("Content-Length", str(len(out))))
    # no-store to avoid stale HTML
    nh = [(k,v) for (k,v) in nh if str(k).lower()!="cache-control"]
    nh.append(("Cache-Control","no-store"))

    start_response(status, nh, cap.get("exc_info"))
    return [out]

application = _vsp__tabs4_html_cachebust_wrapper
app = application
# ===================== /VSP_P1_TABS4_HTML_CACHEBUST_OUTER_V1 =====================
''').rstrip() + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + block, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
else
  echo "[WARN] systemctl not found; restart service manually if needed."
fi

echo "[DONE] Outer HTML cachebust wrapper for 4 tabs"
