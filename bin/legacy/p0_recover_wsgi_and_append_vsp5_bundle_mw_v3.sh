#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need ls; need head; need sort; need tail; need grep; need curl

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

echo "== find latest backup from v2 injection attempt =="
BAK="$(ls -1t ${WSGI}.bak_vsp5_bundle_inject_mw_v2_* 2>/dev/null | head -n1 || true)"
if [ -z "${BAK:-}" ] || [ ! -f "$BAK" ]; then
  echo "[ERR] cannot find backup ${WSGI}.bak_vsp5_bundle_inject_mw_v2_*"
  echo "[HINT] list backups: ls -1 ${WSGI}.bak_* | tail"
  exit 2
fi
echo "[PICK] BAK=$BAK"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BAK" "$WSGI"
cp -f "$WSGI" "${WSGI}.bak_recovered_${TS}"
echo "[OK] restored WSGI from backup + snapshot ${WSGI}.bak_recovered_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_VSP5_BUNDLE_INJECT_MW_V3"
if marker in s:
    print("[OK] MW v3 already present; skip append")
    raise SystemExit(0)

mw = r'''

# ===================== VSP_P0_VSP5_BUNDLE_INJECT_MW_V3 =====================
# Inject vsp_bundle_commercial_v2.js into /vsp5 HTML if missing (prefer before gate_story).
import re as _re

class _VSP5BundleInjectMW_V3:
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
            return lambda x: None  # delay

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

        ctype = ""
        for k, v in headers:
            if str(k).lower() == "content-type":
                ctype = str(v)
                break

        if "text/html" not in ctype.lower():
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

        # reuse ?v= from gate_story if possible
        m = _re.search(r'vsp_dashboard_gate_story_v1\.js\?v=([0-9A-Za-z_.:-]+)', html)
        v = m.group(1) if m else ""
        bundle_tag = f'<script src="/static/js/vsp_bundle_commercial_v2.js?v={v}"></script>' if v \
                     else '<script src="/static/js/vsp_bundle_commercial_v2.js"></script>'

        html2 = html

        # prefer insert before gate_story
        if "vsp_dashboard_gate_story_v1.js" in html2:
            html2, n = _re.subn(
                r'(<script[^>]+vsp_dashboard_gate_story_v1\.js[^>]*></script>)',
                bundle_tag + r"\n\1",
                html2,
                count=1
            )

        # fallback before </body>
        if "vsp_bundle_commercial_v2.js" not in html2:
            if _re.search(r"</body\s*>", html2, flags=_re.I):
                html2 = _re.sub(r"(</body\s*>)", bundle_tag + r"\n\1", html2, count=1, flags=_re.I)
            else:
                html2 = html2 + "\n" + bundle_tag + "\n"

        body2 = html2.encode("utf-8")

        # rewrite Content-Length
        new_headers = [(k, v) for (k, v) in headers if str(k).lower() != "content-length"]
        new_headers.append(("Content-Length", str(len(body2))))

        start_response(status, new_headers, exc_info)
        return [body2]

# wrap gunicorn entry
try:
    if "application" in globals():
        globals()["application"] = _VSP5BundleInjectMW_V3(globals()["application"])
    if "app" in globals():
        globals()["app"] = globals().get("application", globals()["app"])
    print("[VSP5_BUNDLE_INJECT_MW_V3] enabled")
except Exception as _e:
    print("[VSP5_BUNDLE_INJECT_MW_V3] enable failed:", _e)
# ===================== /VSP_P0_VSP5_BUNDLE_INJECT_MW_V3 =====================

'''

p.write_text(s + mw, encoding="utf-8")
print("[OK] appended MW v3 at end of file")
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC"

echo "== health check =="
curl -fsS -I "$BASE/vsp5" | head -n 8 || { echo "[ERR] /vsp5 not reachable"; exit 2; }

echo "== verify bundle injected into /vsp5 html =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_bundle_commercial_v2.js" | head -n 5 || {
  echo "[ERR] /vsp5 still missing bundle include (MW not applied?)"; exit 2;
}

echo "[DONE] OK. Hard refresh: Ctrl+Shift+R  $BASE/vsp5"
