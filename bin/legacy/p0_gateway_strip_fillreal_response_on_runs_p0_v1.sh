#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_strip_fillreal_runs_${TS}"
echo "[BACKUP] ${F}.bak_strip_fillreal_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_STRIP_FILLREAL_RUNS_RESPONSE_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Append a generic WSGI middleware that strips the fill_real <script> for /runs only
mw = f"""

# {MARK}
def _vsp_mw_strip_fillreal_on_runs(app):
    \"\"\"WSGI MW: for /runs, strip vsp_fill_real_data_5tabs_p1_v1.js script tag from HTML.\"\"\"
    def _mw(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not (path == "/runs" or path.startswith("/runs/")):
            return app(environ, start_response)

        captured = {{"status": None, "headers": None, "exc": None}}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # delay actual start_response until body is processed

        it = app(environ, _sr)
        chunks = []
        try:
            for c in it:
                if c:
                    chunks.append(c)
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close): close()
            except Exception:
                pass

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        body = b"".join(chunks)

        # detect content-type
        ct = ""
        for k, v in headers:
            if str(k).lower() == "content-type":
                ct = str(v)
                break

        if body and ("text/html" in ct.lower()):
            try:
                html = body.decode("utf-8", "replace")
                # remove script tag (allow quotes, attrs, querystring)
                html2 = re.sub(
                    r\"\"\"\\s*<script[^>]+src=['\\"]?/static/js/vsp_fill_real_data_5tabs_p1_v1\\.js[^'\\"]*['\\"][^>]*>\\s*</script>\\s*\"\"\",\n
                    \"\",\n
                    html,\n
                    flags=re.I\n
                )
                if html2 != html:
                    body = html2.encode("utf-8")
                    # fix content-length
                    headers = [(k, v) for (k, v) in headers if str(k).lower() != "content-length"]
                    headers.append(("Content-Length", str(len(body))))
            except Exception:
                pass

        start_response(status, headers, captured["exc"])
        return [body]
    return _mw

"""
# ensure we don't break file: add at end
s2 = s + mw

# 2) Hook middleware into WSGI entrypoint
patched = False

# pattern A: app.wsgi_app = ...
m = re.search(r'^(?P<indent>\\s*)(?P<lhs>app\\.wsgi_app)\\s*=\\s*(?P<rhs>.+)\\s*$', s2, flags=re.M)
if m and MARK not in s:
    # If already has app.wsgi_app assignment, wrap it after that line (non-invasive)
    insert_pos = m.end()
    s2 = s2[:insert_pos] + f"\\n{m.group('indent')}app.wsgi_app = _vsp_mw_strip_fillreal_on_runs(app.wsgi_app)\\n" + s2[insert_pos:]
    patched = True
else:
    # pattern B: application = app (common gunicorn entry)
    m2 = re.search(r'^(?P<indent>\\s*)application\\s*=\\s*(?P<rhs>app|create_app\\(\\))\\s*$', s2, flags=re.M)
    if m2:
        insert_pos = m2.end()
        s2 = s2[:insert_pos] + f"\\n{m2.group('indent')}application = _vsp_mw_strip_fillreal_on_runs(application)\\n" + s2[insert_pos:]
        patched = True
    else:
        # pattern C: last resort: if there is a variable named app, wrap app itself (gunicorn may point to app)
        if re.search(r'^\\s*app\\s*=\\s*', s2, flags=re.M):
            s2 += "\\n# fallback hook\\ntry:\\n    app.wsgi_app = _vsp_mw_strip_fillreal_on_runs(app.wsgi_app)\\nexcept Exception:\\n    pass\\n"
            patched = True

p.write_text(s2, encoding="utf-8")
print(f"[OK] injected mw strip + hook: {patched}")
PY

# restart (reuse your stable launcher)
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify /runs no fillreal injector =="
if curl -sS http://127.0.0.1:8910/runs | grep -n "vsp_fill_real_data_5tabs_p1_v1\\.js" ; then
  echo "[ERR] still injected"
  exit 1
else
  echo "[OK] no fillreal on /runs"
fi

echo "== quick sanity =="
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,8p'
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=1" | sed -n '1,12p'
