#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p2_wsgimw_${TS}"
echo "[BACKUP] ${W}.bak_p2_wsgimw_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_WSGI_MW_INJECT_BUNDLE_TABS5_V1E"
if MARK in s:
    print("[OK] already has:", MARK)
else:
    block = f"""

# ===================== {MARK} =====================
# WSGI middleware: inject bundle into HTML for tabs5 routes even if `application` is not a Flask app.
try:
    import re as _re
    import time as _time

    _VSP_P2_BUNDLE_FALLBACK_V_MW = str(int(_time.time()))
    _VSP_P2_TARGET_PATHS = set(["/vsp5","/runs","/settings","/data_source","/rule_overrides"])

    def _vsp_p2_wsgi_mw_inject_bundle(app):
        def _wrapped(environ, start_response):
            try:
                path = (environ.get("PATH_INFO") or "") or ""
                if path == "/":
                    path = "/vsp5"

                # Fast path: not our tabs pages => passthrough
                if path not in _VSP_P2_TARGET_PATHS:
                    return app(environ, start_response)

                captured = {{"status": None, "headers": None, "exc": None}}

                def _sr(status, headers, exc_info=None):
                    captured["status"] = status
                    captured["headers"] = list(headers) if headers else []
                    captured["exc"] = exc_info
                    # We delay calling real start_response until we potentially edit body
                    return None

                it = app(environ, _sr)

                body_chunks = []
                try:
                    for c in it:
                        if c:
                            body_chunks.append(c)
                finally:
                    try:
                        close = getattr(it, "close", None)
                        if callable(close):
                            close()
                    except Exception:
                        pass

                status = captured["status"] or "200 OK"
                headers = captured["headers"] or []

                # Determine content-type
                ct = ""
                for (k, v) in headers:
                    if k.lower() == "content-type":
                        ct = (v or "").lower()
                        break

                # Only touch HTML
                if "text/html" not in ct:
                    # call real start_response + return original body
                    start_response(status, headers, captured["exc"])
                    return body_chunks

                body = b"".join(body_chunks)
                text = body.decode("utf-8", errors="ignore")

                # Reuse digits from autorid if present
                mm = _re.search(r'vsp_tabs4_autorid_v1\\.js\\?v=([0-9]{{6,}})', text)
                v = mm.group(1) if mm else _VSP_P2_BUNDLE_FALLBACK_V_MW

                if "vsp_bundle_tabs5_v1.js" in text:
                    # Add debug header so we can see middleware executed
                    new_headers = [(k, v2) for (k, v2) in headers if k.lower() != "content-length"]
                    new_headers.append(("X-VSP-P2-BUNDLE", "present"))
                    start_response(status, new_headers, captured["exc"])
                    return [body]

                tag = f'<script defer src="/static/js/vsp_bundle_tabs5_v1.js?v={{v}}"></script>'

                if "</body>" in text:
                    text = text.replace("</body>", tag + "\\n</body>", 1)
                elif "</head>" in text:
                    text = text.replace("</head>", tag + "\\n</head>", 1)
                else:
                    text = text + "\\n" + tag + "\\n"

                out = text.encode("utf-8")
                new_headers = [(k, v2) for (k, v2) in headers if k.lower() != "content-length"]
                new_headers.append(("Content-Length", str(len(out))))
                new_headers.append(("X-VSP-P2-BUNDLE", "injected"))
                start_response(status, new_headers, captured["exc"])
                return [out]

            except Exception:
                # Hard fail-safe: never break UI
                return app(environ, start_response)
        return _wrapped

    _orig = globals().get("application")
    if callable(_orig):
        globals()["_vsp_p2_application_orig"] = _orig
        globals()["application"] = _vsp_p2_wsgi_mw_inject_bundle(_orig)
except Exception:
    pass
# ===================== /{MARK} =====================

""".rstrip() + "\n"
    p.write_text(s + block, encoding="utf-8")
    print("[OK] appended:", MARK)

py_compile.compile(str(p), doraise=True)
print("[OK] wsgi compiles")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== [SELF-CHECK] /vsp5 header =="
curl -fsS -I "$BASE/vsp5" | egrep -i 'HTTP/|Server|Content-Type|Content-Length|X-VSP-P2-BUNDLE' || true

echo "== [SELF-CHECK] /vsp5 body has bundle =="
H="$(curl -fsS "$BASE/vsp5")"
echo "$H" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on /vsp5"; exit 3; }
echo "[OK] bundle present on /vsp5"

echo "== [SELF-CHECK] 5 pages have bundle =="
for P in /vsp5 /runs /settings /data_source /rule_overrides; do
  HTML="$(curl -fsS "$BASE$P")"
  echo "$HTML" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on $P"; exit 3; }
  echo "[OK] $P"
done

echo "[DONE] P2 WSGI middleware inject bundle OK"
