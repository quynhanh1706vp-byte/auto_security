#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"
TS="$(date +%Y%m%d_%H%M%S)"
V="cio_${TS}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need grep; need head; need python3

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

cp -f "$WSGI" "${WSGI}.bak_inject_cio_vsp5_${TS}"
echo "[BACKUP] ${WSGI}.bak_inject_cio_vsp5_${TS}"

"$PY" - <<PY
from pathlib import Path
import re, time, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="### === CIO INJECT SHELL VSP5 ONLY (AUTO) ==="
END ="### === END CIO INJECT SHELL VSP5 ONLY (AUTO) ==="

block = f'''
### === CIO INJECT SHELL VSP5 ONLY (AUTO) ===
# Ensure /vsp5 always loads CIO shell CSS/JS even if template differs.
def _cio_inject_shell_into_vsp5_html(app):
    import re
    css = b'<link rel="stylesheet" href="/static/css/vsp_cio_shell_v1.css?v={V}"/>'
    js  = b'<script defer src="/static/js/vsp_cio_shell_apply_v1.js?v={V}"></script>'
    def _wrap(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        cap = {{"status": None, "headers": None, "exc": None}}
        def _sr(status, headers, exc_info=None):
            cap["status"]=status
            cap["headers"]=list(headers) if headers else []
            cap["exc"]=exc_info
            return None

        body_iter = app(environ, _sr)

        try:
            if path != "/vsp5":
                def passthru():
                    start_response(cap["status"], cap["headers"] or [], cap["exc"])
                    for c in body_iter: yield c
                return passthru()

            headers = cap["headers"] or []
            ct = ""
            for k,v in headers:
                if str(k).lower()=="content-type":
                    ct=str(v).lower()
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
                if isinstance(c, str): c=c.encode("utf-8","ignore")
                chunks.append(c)
                total += len(c)
                if total > 2_500_000:
                    # safety: don't buffer huge pages
                    def passthru3():
                        start_response(cap["status"], headers, cap["exc"])
                        for x in chunks: yield x
                        for x in body_iter: yield x
                    return passthru3()

            data=b"".join(chunks)

            # inject CSS if missing
            if b"vsp_cio_shell_v1.css" not in data:
                if b"</head>" in data.lower():
                    data = re.sub(br"(?i)</head>", css + b"\\n</head>", data, count=1)
                else:
                    data = css + b"\\n" + data

            # inject JS if missing
            if b"vsp_cio_shell_apply_v1.js" not in data:
                if b"</body>" in data.lower():
                    data = re.sub(br"(?i)</body>", js + b"\\n</body>", data, count=1)
                else:
                    data = data + b"\\n" + js

            new_headers=[]
            for k,v in headers:
                if str(k).lower()=="content-length":
                    continue
                new_headers.append((k,v))
            new_headers.append(("Content-Length", str(len(data))))

            start_response(cap["status"], new_headers, cap["exc"])
            return [data]
        except Exception:
            start_response(cap["status"], cap["headers"] or [], cap["exc"])
            return body_iter
    return _wrap
### === END CIO INJECT SHELL VSP5 ONLY (AUTO) ===
'''.strip("\\n") + "\\n"

# remove old block if exists
if MARK in s and END in s:
    s = re.sub(rf"{re.escape(MARK)}.*?{re.escape(END)}\\n?", "", s, flags=re.S)

s = s.rstrip() + "\\n\\n" + block

# attach wrapper once (try application first, then app)
attach = "application = _cio_inject_shell_into_vsp5_html(application)"
if attach not in s:
    s += "\\ntry:\\n    application = _cio_inject_shell_into_vsp5_html(application)\\nexcept Exception:\\n    try:\\n        application = _cio_inject_shell_into_vsp5_html(app)\\n    except Exception:\\n        pass\\n"

bak = p.with_name(p.name + f".bak_injectcio_block_{time.strftime('%Y%m%d_%H%M%S')}")
bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
p.write_text(s, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok; backup:", bak.name)
PY

echo "== [2] Restart =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [3] Verify /vsp5 now contains CIO shell tags =="
python3 - <<'PY'
import re
from urllib.request import Request, urlopen
BASE="http://127.0.0.1:8910"
req=Request(BASE+"/vsp5", headers={"User-Agent":"vsp-probe/1.0"})
with urlopen(req, timeout=3) as r:
    html=r.read(250000).decode("utf-8","ignore")
print("CIO_CSS=", "YES" if re.search(r"vsp_cio_shell_v1\.css", html, re.I) else "NO")
print("CIO_JS =", "YES" if re.search(r"vsp_cio_shell_apply_v1\.js", html, re.I) else "NO")
print("LUXE  =", "YES" if re.search(r"vsp_dashboard_luxe_v1\.js", html, re.I) else "NO")
PY

echo "[DONE] Ctrl+Shift+R on /vsp5."
