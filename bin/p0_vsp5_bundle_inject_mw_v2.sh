#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_vsp5_bundle_inject_mw_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_vsp5_bundle_inject_mw_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_VSP5_BUNDLE_INJECT_MW_V2"
if marker in s:
    print("[OK] MW already present")
    raise SystemExit(0)

anchor = "VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C"
i = s.find(anchor)

mw = r'''
# ===================== VSP_P0_VSP5_BUNDLE_INJECT_MW_V2 =====================
# Inject vsp_bundle_commercial_v2.js into /vsp5 HTML if missing (prefer before gate_story).
import re as _re

class _VSP5BundleInjectMW_V2:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        try:
            path = environ.get("PATH_INFO") or ""
        except Exception:
            path = ""

        if path != "/vsp5":
            return self.app(environ, start_response)

        captured = {}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc_info"] = exc_info
            # delay real start_response until we possibly rewrite body
            return lambda x: None

        resp_iter = self.app(environ, _sr)

        try:
            body = b"".join(resp_iter or [])
        finally:
            try:
                close = getattr(resp_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        headers = captured.get("headers", [])
        status = captured.get("status", "200 OK")
        exc_info = captured.get("exc_info", None)

        # detect content-type
        ctype = ""
        for k, v in headers:
            if str(k).lower() == "content-type":
                ctype = str(v)
                break

        if "text/html" not in ctype.lower():
            # passthrough
            start_response(status, headers, exc_info)
            return [body]

        try:
            html = body.decode("utf-8", "replace")
        except Exception:
            start_response(status, headers, exc_info)
            return [body]

        if "vsp_bundle_commercial_v2.js" in html:
            start_response(status, headers, exc_info)
            return [body]

        # try reuse ?v= from gate_story
        m = _re.search(r'vsp_dashboard_gate_story_v1\.js\?v=([0-9A-Za-z_.:-]+)', html)
        v = m.group(1) if m else ""
        if v:
            bundle_tag = f'<script src="/static/js/vsp_bundle_commercial_v2.js?v={v}"></script>'
        else:
            bundle_tag = '<script src="/static/js/vsp_bundle_commercial_v2.js"></script>'

        # insert before first gate_story script if exists, else before </body>
        if "vsp_dashboard_gate_story_v1.js" in html:
            html2, n = _re.subn(
                r'(<script[^>]+vsp_dashboard_gate_story_v1\.js[^>]*></script>)',
                bundle_tag + r"\n\1",
                html,
                count=1
            )
            if n == 0:
                html2 = html
        else:
            html2 = html

        if html2 == html:
            # fallback: before </body>
            if _re.search(r"</body\s*>", html, flags=_re.I):
                html2 = _re.sub(r"(</body\s*>)", bundle_tag + r"\n\1", html, count=1, flags=_re.I)
            else:
                html2 = html + "\n" + bundle_tag + "\n"

        body2 = html2.encode("utf-8")

        # rewrite Content-Length
        new_headers = [(k, v) for (k, v) in headers if str(k).lower() != "content-length"]
        new_headers.append(("Content-Length", str(len(body2))))

        start_response(status, new_headers, exc_info)
        return [body2]

# wrap gunicorn entry
try:
    if "application" in globals():
        application = _VSP5BundleInjectMW_V2(application)
        globals()["application"] = application
    if "app" in globals():
        # keep compatibility: app should point to the same callable
        globals()["app"] = globals().get("application", globals()["app"])
    print("[VSP5_BUNDLE_INJECT_MW_V2] enabled")
except Exception as _e:
    print("[VSP5_BUNDLE_INJECT_MW_V2] enable failed:", _e)
# ===================== /VSP_P0_VSP5_BUNDLE_INJECT_MW_V2 =====================
'''

if i >= 0:
    s2 = s[:i] + mw + "\n" + s[i:]
    print("[OK] inserted MW before anchor:", anchor)
else:
    # append near end as fallback
    s2 = s + "\n" + mw + "\n"
    print("[WARN] anchor not found; appended MW at end")

p.write_text(s2, encoding="utf-8")
print("[OK] wrote MW block")
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC"

echo "== verify /vsp5 has bundle now =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_bundle_commercial_v2.js" | head -n 5 || {
  echo "[ERR] /vsp5 still missing bundle include"; exit 2;
}

echo "== verify ordering (bundle before gate_story if possible) =="
curl -fsS "$BASE/vsp5" | python3 - <<'PY'
import sys
h=sys.stdin.read().splitlines()
idx_b=next((i for i,l in enumerate(h) if "vsp_bundle_commercial_v2.js" in l), -1)
idx_g=next((i for i,l in enumerate(h) if "vsp_dashboard_gate_story_v1.js" in l), -1)
print("idx_bundle=",idx_b+1,"idx_gate_story=",idx_g+1,"ok_order=",(idx_b!=-1 and idx_g!=-1 and idx_b<idx_g))
PY

echo "[DONE] Hard refresh: Ctrl+Shift+R  $BASE/vsp5"
