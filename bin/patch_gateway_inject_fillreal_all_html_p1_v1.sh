#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fillreal_gateway_${TS}"
echo "[BACKUP] ${F}.bak_fillreal_gateway_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_GATEWAY_INJECT_FILLREAL_ALLHTML_P1_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

inject = r'''
# === VSP_GATEWAY_INJECT_FILLREAL_ALLHTML_P1_V1 ===
try:
    _vsp_app = app  # Flask app name commonly "app"
except Exception:
    _vsp_app = None

if _vsp_app is not None:
    @_vsp_app.after_request
    def _vsp_p1_inject_fillreal_all_html(resp):
        try:
            ct = (resp.headers.get("Content-Type") or "").lower()
            if "text/html" not in ct:
                return resp
            # avoid streaming / passthrough
            if getattr(resp, "direct_passthrough", False):
                return resp

            b = resp.get_data()
            if not b:
                return resp
            html = b.decode("utf-8", errors="replace")

            # already injected?
            if "vsp_fill_real_data_5tabs_p1_v1.js" in html or "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" in html:
                return resp

            tag = (
                "\n<!-- VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY -->\n"
                "<script src=\"/static/js/vsp_fill_real_data_5tabs_p1_v1.js\"></script>\n"
                "<!-- /VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY -->\n"
            )

            if "</body>" in html:
                html = html.replace("</body>", tag + "</body>")
            elif "</html>" in html:
                html = html.replace("</html>", tag + "</html>")
            else:
                html = html + tag

            resp.set_data(html.encode("utf-8"))
            # Content-Length must be recalculated
            try:
                resp.headers.pop("Content-Length", None)
            except Exception:
                pass
            return resp
        except Exception:
            return resp
# === /VSP_GATEWAY_INJECT_FILLREAL_ALLHTML_P1_V1 ===
'''

# find a safe insertion point: after Flask app creation (look for "app = Flask(")
m = re.search(r"^app\s*=\s*Flask\(", s, flags=re.M)
if not m:
    # fallback: insert near end, before "application = app" or last lines
    m2 = re.search(r"^application\s*=\s*app\s*$", s, flags=re.M)
    if m2:
        ins_at = m2.start()
        s2 = s[:ins_at] + inject + "\n" + s[ins_at:]
    else:
        s2 = s + "\n" + inject + "\n"
else:
    # insert after the line that defines app (end of that statement line)
    # find line end
    line_end = s.find("\n", m.start())
    if line_end < 0:
        line_end = len(s)
    s2 = s[:line_end+1] + inject + "\n" + s[line_end+1:]

# add marker comment
s2 = s2.replace("# === VSP_GATEWAY_INJECT_FILLREAL_ALLHTML_P1_V1 ===",
                f"# === {MARK} ===")

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] restart UI:"
echo "  sudo systemctl restart vsp-ui-8910.service"
