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
cp -f "$W" "${W}.bak_p2_injbundle_v1b_${TS}"
echo "[BACKUP] ${W}.bak_p2_injbundle_v1b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_INJECT_BUNDLE_TABS5_WSGI_V1"
start = f"# ===================== {MARK} ====================="
end   = f"# ===================== /{MARK} ====================="

if start not in s or end not in s:
    raise SystemExit(f"[ERR] marker block not found: {MARK}")

new_block = f"""
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

            # Some responses may be passthrough/streaming-like; force readable body
            if hasattr(resp, "direct_passthrough") and getattr(resp, "direct_passthrough", False):
                try:
                    resp.direct_passthrough = False
                except Exception:
                    pass

            ct = (resp.headers.get("Content-Type","") or "").lower()
            mt = (getattr(resp, "mimetype", "") or "").lower()
            if ("text/html" not in ct) and (mt != "text/html"):
                return resp

            body = resp.get_data(as_text=True)  # type: ignore
            if "vsp_bundle_tabs5_v1.js" in body:
                try: resp.headers["X-VSP-P2-BUNDLE"] = "present"
                except Exception: pass
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
            resp.headers["Content-Length"] = str(len(body.encode("utf-8")))
            try: resp.headers["X-VSP-P2-BUNDLE"] = "injected"
            except Exception: pass
            return resp
        except Exception:
            try: resp.headers["X-VSP-P2-BUNDLE"] = "err"
            except Exception: pass
            return resp
except Exception:
    pass
# ===================== /{MARK} =====================
""".lstrip("\n")

pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), flags=re.S)
s2, n = pattern.subn(new_block.rstrip("\n"), s, count=1)
if n != 1:
    raise SystemExit(f"[ERR] failed to replace marker block: replaced={n}")

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] updated block:", MARK)
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== [SELF-CHECK] headers + bundle present =="
for P in /vsp5 /runs /settings /data_source /rule_overrides; do
  echo "-- $P (HEAD) --"
  curl -fsS -I "$BASE$P" | sed -n '1,20p' | egrep -i 'HTTP/|Content-Type|X-VSP-P2-BUNDLE|Content-Length' || true

  echo "-- $P (BODY grep) --"
  H="$(curl -fsS "$BASE$P")"
  echo "$H" | grep -q "vsp_tabs4_autorid_v1.js" || { echo "[ERR] missing autorid on $P"; exit 3; }
  echo "$H" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on $P"; exit 3; }
  echo "[OK] $P"
done

echo "[DONE] V1B inject bundle OK"
