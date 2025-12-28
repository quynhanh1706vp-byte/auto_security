#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_vsp5dedupe_${TS}"
echo "[BACKUP] ${WSGI}.bak_vsp5dedupe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
else:
    mw = r'''
# ===================== VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V1 =====================
import re as _re

class _Vsp5HtmlDedupeGateStoryMW:
    __slots__ = ("app",)
    def __init__(self, app):
        self.app = app
        try:
            setattr(self.app, "__vsp_p0_vsp5_html_dedupe_gate_story_mw_v1", True)
        except Exception:
            pass

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        # only touch Dashboard
        if not (path == "/vsp5" or path.startswith("/vsp5/")):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers)
            return start_response(status, headers, exc_info)

        it = self.app(environ, _sr)

        ctype = ""
        try:
            for k, v in (captured["headers"] or []):
                if str(k).lower() == "content-type":
                    ctype = str(v)
                    break
        except Exception:
            ctype = ""

        # Only rewrite html
        if "text/html" not in (ctype or "").lower():
            return it

        # Join body (vsp5 html is tiny)
        body_chunks = []
        try:
            for chunk in it:
                body_chunks.append(chunk)
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close): close()
            except Exception:
                pass

        body = b"".join(body_chunks)
        try:
            html = body.decode("utf-8", errors="replace")
        except Exception:
            return [body]

        # Dedupe gate_story tags: keep FIRST only
        pat = _re.compile(r'(?is)<script[^>]+src="/static/js/vsp_dashboard_gate_story_v1\.js[^"]*"[^>]*>\s*</script>')
        matches = list(pat.finditer(html))
        if len(matches) > 1:
            keep0 = matches[0].span()
            # remove all after first (from end to start to keep indexes stable)
            spans = [m.span() for m in matches[1:]]
            for a, b in sorted(spans, key=lambda x: x[0], reverse=True):
                html = html[:a] + "" + html[b:]

        out = html.encode("utf-8", errors="ignore")

        # Fix Content-Length
        new_headers = []
        for k, v in (captured["headers"] or []):
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k, v))
        new_headers.append(("Content-Length", str(len(out))))

        # Re-send headers once
        try:
            start_response(captured["status"] or "200 OK", new_headers)
        except Exception:
            # if already started, just return body
            pass

        return [out]

# Wrap application if present
try:
    _app_obj = application
except Exception:
    _app_obj = None

if _app_obj is not None and not getattr(_app_obj, "__vsp_p0_vsp5_html_dedupe_gate_story_mw_v1", False):
    application = _Vsp5HtmlDedupeGateStoryMW(_app_obj)
# ===================== /VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V1 =====================
'''
    s = s + "\n\n" + mw
    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", MARK)

PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify /vsp5 gate_story count should be 1 =="
COUNT="$(curl -fsS "$BASE/vsp5" | grep -o 'vsp_dashboard_gate_story_v1.js' | wc -l | tr -d ' ')"
echo "gate_story_count=$COUNT"
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
