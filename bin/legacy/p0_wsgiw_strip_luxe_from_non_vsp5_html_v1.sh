#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need grep; need head; need python3

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_strip_luxe_${TS}"
echo "[BACKUP] ${WSGI}.bak_strip_luxe_${TS}"

echo "== [1] Patch WSGI: strip luxe <script> from non-/vsp5 HTML (idempotent) =="
"$PY" - <<'PY'
from pathlib import Path
import re, time, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="### === CIO STRIP LUXE NON-VSP5 HTML (AUTO) ==="
END ="### === END CIO STRIP LUXE NON-VSP5 HTML (AUTO) ==="

block = r'''
### === CIO STRIP LUXE NON-VSP5 HTML (AUTO) ===
# Why: luxe dashboard JS must only load on /vsp5. Some shells may include it globally.
# This middleware removes the luxe <script> tag from HTML responses for routes != /vsp5.
def _cio_strip_luxe_from_html(app):
    import re
    _pat = re.compile(rb'<script[^>]+vsp_dashboard_luxe_v1\.js[^>]*>\s*</script>\s*', re.I)
    def _wrap(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        cap = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            cap["status"]=status
            cap["headers"]=list(headers) if headers else []
            cap["exc"]=exc_info
            return None

        body_iter = app(environ, _sr)
        # If not HTML or it's /vsp5, pass through untouched
        try:
            if path == "/vsp5":
                def passthru():
                    start_response(cap["status"], cap["headers"], cap["exc"])
                    for c in body_iter: yield c
                return passthru()

            headers = cap["headers"] or []
            ct = ""
            for k,v in headers:
                if str(k).lower() == "content-type":
                    ct = str(v).lower()
                    break
            if "text/html" not in ct:
                def passthru2():
                    start_response(cap["status"], headers, cap["exc"])
                    for c in body_iter: yield c
                return passthru2()

            chunks=[]
            total=0
            for c in body_iter:
                if c is None: continue
                if isinstance(c, str):
                    c=c.encode("utf-8", "ignore")
                chunks.append(c)
                total += len(c)
                if total > 2_500_000:  # safety: don't buffer huge responses
                    def passthru3():
                        start_response(cap["status"], headers, cap["exc"])
                        for x in chunks: yield x
                        for x in body_iter: yield x
                    return passthru3()

            data=b"".join(chunks)
            if b"vsp_dashboard_luxe_v1.js" in data:
                data2=_pat.sub(b"", data)
            else:
                data2=data

            # adjust headers
            new_headers=[]
            for k,v in headers:
                if str(k).lower()=="content-length":
                    continue
                new_headers.append((k,v))
            new_headers.append(("Content-Length", str(len(data2))))

            start_response(cap["status"], new_headers, cap["exc"])
            return [data2]
        except Exception:
            start_response(cap["status"], cap["headers"] or [], cap["exc"])
            return body_iter
    return _wrap
### === END CIO STRIP LUXE NON-VSP5 HTML (AUTO) ===
'''.strip("\n") + "\n"

# remove older block if exists, then append fresh
if MARK in s and END in s:
    s = re.sub(rf"{re.escape(MARK)}.*?{re.escape(END)}\n?", "", s, flags=re.S)

s = s.rstrip() + "\n\n" + block

# attach wrapper once
if "_cio_strip_luxe_from_html(" not in s:
    s += "\ntry:\n    application = _cio_strip_luxe_from_html(application)\nexcept Exception:\n    try:\n        application = _cio_strip_luxe_from_html(app)\n    except Exception:\n        pass\n"

bak=p.with_name(p.name+f".bak_stripblock_{time.strftime('%Y%m%d_%H%M%S')}")
bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok; backup:", bak.name)
PY

echo
echo "== [2] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo
echo "== [3] Verify: /data_source must NOT contain luxe script tag now =="
if curl -fsS --max-time 3 "$BASE/data_source" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 3; then
  echo "[ERR] still found luxe in /data_source HTML"
  exit 4
else
  echo "[OK] luxe removed from /data_source HTML"
fi

echo
echo "[DONE] Now Ctrl+Shift+R in browser on /data_source and confirm Network filter 'luxe' = 0 requests."
