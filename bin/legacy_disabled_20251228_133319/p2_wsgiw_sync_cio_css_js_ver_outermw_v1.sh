#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
SVC_CANDIDATES=("${VSP_UI_SVC:-vsp-ui-8910.service}" "vsp-ui-8910.service" "vsp-ui-gateway.service")
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need head; need grep

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
cp -f "$WSGI" "${WSGI}.bak_sync_cio_css_js_${TS}"
echo "[BACKUP] ${WSGI}.bak_sync_cio_css_js_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_SYNC_CIO_CSS_JS_VER_OUTERMW_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

mw = r'''
# ''' + MARK + r'''
# Ensure CIO shell CSS/JS version stays consistent (avoid mixed ?v=cio_* vs ?v=timestamp)
import re as _re

class _VspCioCssJsVerSyncMw:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        captured = {"status": None, "headers": None, "exc": None}
        chunks = []

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # Return a write callable per WSGI spec
            def _write(data):
                if data:
                    chunks.append(data)
            return _write

        result = self.app(environ, _sr)
        try:
            for part in result:
                if part:
                    chunks.append(part)
        finally:
            try:
                close = getattr(result, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        # Determine content-type
        ct = ""
        new_headers = []
        for (k,v) in headers:
            if str(k).lower() == "content-type":
                ct = str(v)
            # drop old content-length (we will recalc if needed)
            if str(k).lower() != "content-length":
                new_headers.append((k,v))

        body = b"".join(chunks)
        # Only touch HTML responses
        if "text/html" in ct.lower() and body:
            try:
                html = body.decode("utf-8", "replace")
                # Extract ver from CIO CSS tag
                m = _re.search(r'vsp_cio_shell_v1\.css\?v=([^"\'<> ]+)', html, _re.I)
                if m:
                    ver = m.group(1)
                    # Force CIO apply JS to use the same ver
                    html2 = _re.sub(
                        r'(vsp_cio_shell_apply_v1\.js\?v=)([^"\'<> ]+)',
                        lambda mm: mm.group(1) + ver,
                        html,
                        flags=_re.I
                    )
                    if html2 != html:
                        body = html2.encode("utf-8")
            except Exception:
                pass

        # Restore headers
        new_headers.append(("Content-Length", str(len(body))))
        start_response(status, new_headers, captured["exc"])
        return [body]

def _vsp_wrap_cio_ver_sync(_obj):
    try:
        return _VspCioCssJsVerSyncMw(_obj)
    except Exception:
        return _obj
'''

# Append middleware + wrap application/app if possible
s2 = s + "\n" + mw + "\n"
# Wrap commonly-used WSGI export variable
# Prefer: application; fallback: app
if re.search(r'(?m)^\s*application\s*=', s2):
    s2 += "\n# wrap existing application\ntry:\n    application = _vsp_wrap_cio_ver_sync(application)\nexcept Exception:\n    pass\n"
else:
    # if app exists, export application
    if re.search(r'(?m)^\s*app\s*=', s2) or "app" in s2:
        s2 += "\n# export application from app (and wrap)\ntry:\n    application = _vsp_wrap_cio_ver_sync(app)\nexcept Exception:\n    try:\n        application = app\n    except Exception:\n        pass\n"

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", MARK)
PY

echo "== [RESTART] =="
for svc in "${SVC_CANDIDATES[@]}"; do
  [ -n "$svc" ] || continue
  if systemctl list-unit-files | grep -q "^${svc}"; then
    echo "[DO] sudo systemctl restart $svc"
    sudo systemctl restart "$svc" || true
  fi
done

echo "== [VERIFY] (CIO JS ver must equal CIO CSS ver on ALL tabs) =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "--- $p ---"
  html="$(curl -fsS --connect-timeout 1 --max-time 4 --range 0-120000 "$BASE$p")"
  css="$(printf "%s" "$html" | grep -oE 'vsp_cio_shell_v1\.css\?v=[^" ]+' | head -n1 || true)"
  js="$(printf "%s" "$html" | grep -oE 'vsp_cio_shell_apply_v1\.js\?v=[^" ]+' | head -n1 || true)"
  echo "CSS=$css"
  echo "JS =$js"
done

echo "[DONE] Ctrl+Shift+R browser."
