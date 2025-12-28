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
cp -f "$W" "${W}.bak_p2_injbundle_${TS}"
echo "[BACKUP] ${W}.bak_p2_injbundle_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_INJECT_BUNDLE_TABS5_WSGI_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# We want to hook right after `app = application` (your file already had that).
m = re.search(r'(^\s*app\s*=\s*application\s*$)', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find line `app = application` to anchor injection")

inject = f"""
# ===================== {MARK} =====================
# Ensure tabs5 bundle exists for main 5 pages, independent of templates.
try:
    from flask import request
    import re as _re
    import time as _time

    _VSP_P2_BUNDLE_FALLBACK_V = str(int(_time.time()))

    @app.after_request
    def _vsp_p2_inject_bundle_tabs5(resp):
        try:
            path = getattr(request, "path", "") or ""
            if path == "/":
                path = "/vsp5"
            if path not in ("/vsp5","/runs","/settings","/data_source","/rule_overrides"):
                return resp

            ct = (resp.headers.get("Content-Type","") or "").lower()
            if "text/html" not in ct:
                return resp

            body = resp.get_data(as_text=True)  # type: ignore
            if "vsp_bundle_tabs5_v1.js" in body:
                return resp

            # Prefer reusing digits v=... from autorid if present in final HTML
            mm = _re.search(r'vsp_tabs4_autorid_v1\\.js\\?v=([0-9]{{6,}})', body)
            v = mm.group(1) if mm else _VSP_P2_BUNDLE_FALLBACK_V

            tag = f'<script defer src="/static/js/vsp_bundle_tabs5_v1.js?v={{v}}"></script>'

            if "</body>" in body:
                body = body.replace("</body>", tag + "\\n</body>", 1)
            elif "</head>" in body:
                body = body.replace("</head>", tag + "\\n</head>", 1)
            else:
                body = body + "\\n" + tag + "\\n"

            resp.set_data(body)  # type: ignore
            # update content-length to avoid truncated responses behind some proxies
            resp.headers["Content-Length"] = str(len(body.encode("utf-8")))
            return resp
        except Exception:
            return resp
except Exception:
    pass
# ===================== /{MARK} =====================
"""

# insert right after the anchor line
pos = m.end(1)
s2 = s[:pos] + inject + s[pos:]
p.write_text(s2, encoding="utf-8")

# compile check (best-effort)
py_compile.compile(str(p), doraise=True)
print("[OK] patched + compiled:", MARK)
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== [SELF-CHECK] bundle present on 5 pages =="
pages=(/vsp5 /runs /settings /data_source /rule_overrides)
for P in "${pages[@]}"; do
  echo "-- $P --"
  H="$(curl -fsS "$BASE$P")"
  echo "$H" | grep -q "vsp_tabs4_autorid_v1.js" || { echo "[ERR] missing autorid on $P"; exit 3; }
  echo "$H" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on $P"; exit 3; }
  echo "$H" | grep -q "{{" && { echo "[ERR] token dirt '{{' on $P"; exit 3; } || true
  echo "$H" | grep -q "}}" && { echo "[ERR] token dirt '}}' on $P"; exit 3; } || true
  echo "[OK] $P"
done

echo "[DONE] P2 inject bundle via WSGI OK"
