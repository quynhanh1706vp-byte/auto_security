#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_fixdedupe_${TS}"
echo "[BACKUP] ${WSGI}.bak_fixdedupe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK1 = "VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V1"
MARK2 = "VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V2"

# Replace whole block if V1 exists
block_re = re.compile(
    r"(?s)# ===================== VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V1 =====================.*?# ===================== /VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V1 ====================="
)

mw_v2 = r'''
# ===================== VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V2 =====================
import re as _re

class _Vsp5HtmlDedupeGateStoryMW_V2:
    __slots__ = ("app",)
    def __init__(self, app):
        self.app = app
        try:
            setattr(self.app, "__vsp_p0_vsp5_html_dedupe_gate_story_mw_v2", True)
        except Exception:
            pass

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if not (path == "/vsp5" or path.startswith("/vsp5/")):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None}

        # IMPORTANT: do NOT call downstream start_response here.
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers)
            return (lambda _x=None: None)

        it = self.app(environ, _sr)

        ctype = ""
        try:
            for k, v in (captured["headers"] or []):
                if str(k).lower() == "content-type":
                    ctype = str(v)
                    break
        except Exception:
            ctype = ""

        if "text/html" not in (ctype or "").lower():
            # pass-through, but must call real start_response now
            start_response(captured["status"] or "200 OK", captured["headers"] or [])
            return it

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
            start_response(captured["status"] or "200 OK", captured["headers"] or [])
            return [body]

        pat = _re.compile(r'(?is)<script[^>]+src="/static/js/vsp_dashboard_gate_story_v1\.js[^"]*"[^>]*>\s*</script>')
        ms = list(pat.finditer(html))
        if len(ms) > 1:
            for a, b in sorted((m.span() for m in ms[1:]), key=lambda x: x[0], reverse=True):
                html = html[:a] + "" + html[b:]

        out = html.encode("utf-8", errors="ignore")

        new_headers = []
        for k, v in (captured["headers"] or []):
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k, v))
        new_headers.append(("Content-Length", str(len(out))))

        start_response(captured["status"] or "200 OK", new_headers)
        return [out]

try:
    _app_obj = application
except Exception:
    _app_obj = None

if _app_obj is not None and not getattr(_app_obj, "__vsp_p0_vsp5_html_dedupe_gate_story_mw_v2", False):
    application = _Vsp5HtmlDedupeGateStoryMW_V2(_app_obj)
# ===================== /VSP_P0_VSP5_HTML_DEDUPE_GATE_STORY_MW_V2 =====================
'''.strip("\n")

if block_re.search(s):
    s = block_re.sub(mw_v2, s)
else:
    if MARK2 not in s:
        s = s + "\n\n" + mw_v2 + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] MW patched to V2 (single start_response)")
PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== wait /vsp5 ready =="
ok=0
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 1 "$BASE/vsp5" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.25
done
if [ "$ok" != "1" ]; then
  echo "[ERR] /vsp5 still not reachable"
  systemctl --no-pager --full status "$SVC" | sed -n '1,40p' || true
  echo "== last error log (best effort) =="
  tail -n 120 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true
  exit 2
fi

echo "== verify gate_story count should be 1 =="
COUNT="$(curl -fsS "$BASE/vsp5" | grep -o 'vsp_dashboard_gate_story_v1.js' | wc -l | tr -d ' ')"
echo "gate_story_count=$COUNT"
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
