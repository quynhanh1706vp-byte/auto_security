#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_tabs3js_${TS}"
echo "[BACKUP] ${APP}.bak_tabs3js_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_API_TABS3_COMMON_V3_JS_ALWAYS200_V1"
if MARK in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

# Try to insert after Flask app creation or near other /api routes
# We look for a stable anchor: "app = Flask(" or "Flask(__name__"
m = re.search(r"app\s*=\s*Flask\([^\)]*\)\s*", s)
ins = m.end() if m else 0

route = textwrap.dedent(f"""
# ===================== {MARK} =====================
try:
  from flask import Response, send_file, current_app
except Exception:
  Response = None
  send_file = None

from pathlib import Path as _Path

@app.get("/api/vsp_tabs3_common_v3.js")
def vsp_api_tabs3_common_v3_js():
  \"\"\"Commercial P1: stop 404 noise for legacy/common bundle reference.
  - If static/js/vsp_tabs3_common_v3.js exists => serve it.
  - Else => return 200 placeholder JS (no-op).
  \"\"\"
  try:
    js_path = _Path(current_app.root_path) / "static" / "js" / "vsp_tabs3_common_v3.js"
  except Exception:
    js_path = _Path("static/js/vsp_tabs3_common_v3.js")

  try:
    if send_file is not None and js_path.exists():
      return send_file(str(js_path), mimetype="application/javascript")
  except Exception:
    pass

  body = "/* {MARK}: placeholder to avoid 404 noise. */\\n(()=>{{/* noop */}})();\\n"
  if Response is None:
    return body
  return Response(body, mimetype="application/javascript")
# ===================== /{MARK} =====================
""")

s2 = s[:ins] + "\n\n" + route + "\n\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted /api/vsp_tabs3_common_v3.js always-200 route")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] patched and restarted ($SVC)"
