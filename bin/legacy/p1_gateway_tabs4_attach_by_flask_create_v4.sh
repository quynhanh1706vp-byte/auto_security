#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_tabs4_attach_v4_${TS}"
echo "[BACKUP] ${W}.bak_tabs4_attach_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_GATEWAY_TABS4_ATTACH_BY_FLASK_CREATE_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# find Flask app creation lines like: application = Flask(...)
# collect all candidates; attach to all to be safe
cand = re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*Flask\s*\(', s, flags=re.M)
cand = list(dict.fromkeys(cand))  # unique preserve order

if not cand:
    raise SystemExit("[FATAL] cannot find any '<name> = Flask(' in gateway file. Need different attach strategy.")

# insert after the first Flask creation line (best spot, early and deterministic)
m = re.search(r'^\s*' + re.escape(cand[0]) + r'\s*=\s*Flask\s*\(.*$', s, flags=re.M)
if not m:
    raise SystemExit("[FATAL] found cand but cannot locate line position.")

insert_pos = m.end()

block = textwrap.dedent(f"""
\n# ===================== {MARK} =====================
# Attach tabs4 autorid injector to Flask app(s) created in this gateway.
def _vsp_tabs4_inject_autorid_after_request_v4(resp):
    try:
        import time, re
        from flask import request
    except Exception:
        return resp

    try:
        p = (request.path or "").rstrip("/") or "/"
    except Exception:
        return resp

    # never touch dashboard
    if p.startswith("/vsp5"):
        return resp

    # only 4 tabs (exclude /reports because JSON)
    targets = {{"/runs", "/runs_reports", "/settings", "/data_source", "/rule_overrides"}}
    if p not in targets:
        return resp

    try:
        ct = (resp.headers.get("Content-Type") or "").lower()
    except Exception:
        ct = ""
    if "text/html" not in ct:
        return resp

    try:
        body = resp.get_data(as_text=True)
    except Exception:
        return resp

    v = str(int(time.time()))

    # sanitize broken src fragments
    try:
        body = re.sub(r"vsp_tabs4_autorid_v1\\.js\\?v=\\{{\\{{[^}}]*\\}}\\}}", "vsp_tabs4_autorid_v1.js?v="+v, body)
        body = re.sub(r"vsp_tabs4_autorid_v1\\.js\\?v=\\{{[^\\s>]+", "vsp_tabs4_autorid_v1.js?v="+v, body)
    except Exception:
        pass

    tag = "\\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\\n<script src=\\\"/static/js/vsp_tabs4_autorid_v1.js?v=" + v + "\\\"></script>\\n"

    # If already present: persist sanitation + add header
    if "vsp_tabs4_autorid_v1.js" in body:
        try:
            resp.set_data(body)
            resp.headers.pop("Content-Length", None)
            resp.headers["Cache-Control"] = "no-store"
            resp.headers["X-VSP-AUTORID-INJECT"] = "1"
        except Exception:
            return resp
        return resp

    # inject robustly: </head> -> </body> -> append
    if "</head>" in body:
        body = body.replace("</head>", tag + "</head>", 1)
    elif "</body>" in body:
        body = body.replace("</body>", tag + "</body>", 1)
    else:
        body = body + tag

    try:
        resp.set_data(body)
        resp.headers.pop("Content-Length", None)
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["X-VSP-AUTORID-INJECT"] = "1"
    except Exception:
        return resp
    return resp

# Attach to all Flask app variables we detected: {cand}
try:
    _VSP_TABS4_FLASK_APPS = {cand!r}
    for _nm in _VSP_TABS4_FLASK_APPS:
        _obj = globals().get(_nm)
        if _obj and hasattr(_obj, "after_request"):
            _obj.after_request(_vsp_tabs4_inject_autorid_after_request_v4)
except Exception:
    pass
# ===================== /{MARK} =====================
""").rstrip() + "\n"

s2 = s[:insert_pos] + block + s[insert_pos:]
W.write_text(s2, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + compiled:", MARK, "attached_to=", cand)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify tabs4 (print OK/WARN explicitly) =="
for p in /runs /runs_reports /settings /data_source /rule_overrides; do
  echo "-- $p --"
  if curl -sS -I -H "Cache-Control: no-cache" "$BASE$p" | grep -qi "X-VSP-AUTORID-INJECT"; then
    echo "[OK] header X-VSP-AUTORID-INJECT present"
  else
    echo "[WARN] header missing"
  fi

  if curl -sS -H "Cache-Control: no-cache" "$BASE$p" | grep -q "vsp_tabs4_autorid_v1.js"; then
    echo "[OK] autorid src present"
    curl -sS -H "Cache-Control: no-cache" "$BASE$p" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 2
  else
    echo "[WARN] autorid src missing"
  fi
done
