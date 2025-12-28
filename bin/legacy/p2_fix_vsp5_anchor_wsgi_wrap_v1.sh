#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_wsgianchor_${TS}"
echo "[BACKUP] ${F}.bak_wsgianchor_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, sys, re, textwrap

MARK="VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1"
p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

block = textwrap.dedent(f"""
# ===================== {MARK} =====================
# WSGI-level safety: ensure /vsp5 HTML contains <div id="vsp-dashboard-main"></div>
def __vsp__wsgi_wrap_inject_vsp5_anchor__(app):
    try:
        import re as _re
    except Exception:
        _re = None

    def _inject(b: bytes) -> bytes:
        try:
            if not b or (b'id="vsp-dashboard-main"' in b):
                return b
            ins = b'\\n<div id="vsp-dashboard-main"></div>\\n'
            if _re is not None:
                m = _re.search(br'<body[^>]*>', b, _re.I)
                if m:
                    return b[:m.end()] + ins + b[m.end():]
            # fallback: put at top
            return ins + b
        except Exception:
            return b

    def _wrapped(environ, start_response):
        path = (environ or {{}}).get("PATH_INFO", "") or ""
        if path != "/vsp5":
            return app(environ, start_response)

        cap = {{}}
        def _sr(status, headers, exc_info=None):
            cap["status"] = status
            cap["headers"] = headers or []
            cap["exc_info"] = exc_info
            # return a write() callable (rarely used). We'll ignore streaming writes.
            return None

        it = app(environ, _sr)
        try:
            body = b"".join(it) if it is not None else b""
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        headers = list(cap.get("headers") or [])
        # detect content-type
        ct = ""
        for k, v in headers:
            if str(k).lower() == "content-type":
                ct = str(v).lower()
                break

        # only inject for html (or when ct missing but body looks like html)
        looks_html = (b"<html" in body[:200].lower() or b"<body" in body[:200].lower())
        if ("text/html" in ct) or (ct == "" and looks_html):
            new = _inject(body)
        else:
            new = body

        # update content-length
        new_headers = []
        for k, v in headers:
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k, v))
        new_headers.append(("Content-Length", str(len(new))))

        start_response(cap.get("status", "200 OK"), new_headers, cap.get("exc_info"))
        return [new]

    return _wrapped

try:
    application = __vsp__wsgi_wrap_inject_vsp5_anchor__(application)
    print("[{MARK}] wrapped WSGI application for /vsp5 anchor")
except Exception as _e:
    print("[{MARK}] WARN: failed to wrap application:", repr(_e))
# ===================== /{MARK} =====================
""").strip("\n") + "\n"

p.write_text(s + "\n" + block, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended + py_compile OK:", MARK)
PY

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC"
sleep 0.6
sudo systemctl status "$SVC" -l --no-pager || true

echo "== verify live html anchor =="
curl -sS "$BASE/vsp5" | grep -n 'id="vsp-dashboard-main"' | head -n 3 || echo "MISSING"
