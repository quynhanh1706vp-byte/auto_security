#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

# pick likely flask entry
TARGET=""
for cand in ui/vsp_demo_app.py vsp_demo_app.py wsgi_vsp_ui_gateway.py app.py; do
  if [ -f "$cand" ]; then TARGET="$cand"; break; fi
done
[ -n "$TARGET" ] || { echo "[ERR] cannot find flask app file (vsp_demo_app.py / wsgi_vsp_ui_gateway.py / app.py)"; exit 2; }

cp -f "$TARGET" "$TARGET.bak_vsp4_inject_${TS}"
echo "[BACKUP] $TARGET.bak_vsp4_inject_${TS}"

python3 - <<PY
from pathlib import Path
import re, time

p = Path("$TARGET")
s = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_VSP4_INJECT_AFTER_REQUEST_V2" in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

m = re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    # fallback: application = Flask(...)
    m = re.search(r'^\s*(application)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot locate Flask() instance var (e.g. app = Flask(...)) in " + str(p))

appvar = m.group(1)
stamp = str(int(time.time()))

snippet = f'''

# ================================
# VSP_VSP4_INJECT_AFTER_REQUEST_V2
# ================================
from flask import request, redirect
import re as _vsp_re

def _vsp__inject_tags_v2(html: str) -> str:
  try:
    # hash normalizer into <head>
    if "vsp_hash_normalize_v1.js" not in html:
      tag = '<script src="/static/js/vsp_hash_normalize_v1.js?v={stamp}"></script>'
      mm = _vsp_re.search(r'<head[^>]*>', html, flags=_vsp_re.I)
      if mm:
        i = mm.end()
        html = html[:i] + "\\n  " + tag + "\\n" + html[i:]
      else:
        html = tag + "\\n" + html

    # loader+features before </body>
    if "vsp_ui_loader_route_v1.js" not in html:
      ins = '\\n  <script src="/static/js/vsp_ui_features_v1.js?v={stamp}"></script>\\n' \\
            '  <script src="/static/js/vsp_ui_loader_route_v1.js?v={stamp}"></script>\\n'
      if "</body>" in html:
        html = html.replace("</body>", ins + "</body>")
      else:
        html += ins
  except Exception:
    pass
  return html

@{appvar}.after_request
def __vsp_after_request_inject_v2(resp):
  try:
    path = (request.path or "").rstrip("/")
    if path == "/vsp4":
      ct = (resp.headers.get("Content-Type","") or "")
      if "text/html" in ct:
        html = resp.get_data(as_text=True)
        html2 = _vsp__inject_tags_v2(html)
        if html2 != html:
          resp.set_data(html2)
  except Exception:
    pass
  return resp
'''.replace("{appvar}", appvar)

# add root redirect only if missing
if re.search(r'@\s*' + re.escape(appvar) + r'\s*\.route\(\s*[\'"]/\s*[\'"]', s, flags=re.M) is None:
    snippet += f"""

@{appvar}.route("/")
def __vsp_root_redirect_v2():
  return redirect("/vsp4/#dashboard")
"""

p.write_text(s + "\n" + snippet + "\n", encoding="utf-8")
print("[OK] patched", p, "appvar=", appvar)
PY

python3 -m py_compile "$TARGET" && echo "[OK] py_compile OK: $TARGET"

echo "== restart 8910 (NO restore) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_8910_no_restore_v1.sh

echo "== verify =="
curl -sSI http://127.0.0.1:8910/ | head -n 8 || true
curl -sS  http://127.0.0.1:8910/vsp4 | grep -n "vsp_ui_loader_route_v1.js" || echo "[ERR] loader still missing in /vsp4"
curl -sS  http://127.0.0.1:8910/vsp4 | grep -n "vsp_hash_normalize_v1.js" || echo "[ERR] hash normalizer still missing in /vsp4"

echo "[NEXT] mở: http://127.0.0.1:8910/  (tự redirect sang /vsp4/#dashboard)"
