#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "$PYF.bak_html_sanitize_v2_${TS}"
echo "[BACKUP] $PYF.bak_html_sanitize_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

m=re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find app = Flask(...)")
appvar=m.group(1)

if "VSP_HTML_SANITIZE_P_SCRIPT_V2" in s:
    print("[OK] sanitize V2 already present")
else:
    s += f"""

# ================================
# VSP_HTML_SANITIZE_P_SCRIPT_V2
# - remove stray script tags like /static/js/P251217_065927?... or /static/js/p251217_065927?...
# ================================
@{appvar}.after_request
def __vsp_html_sanitize_p_script_v2(resp):
  try:
    ct = (resp.headers.get("Content-Type") or "")
    if "text/html" in ct:
      html = resp.get_data(as_text=True)
      # remove <script src="/static/js/P...._......"> stray tags (case-insensitive P/p)
      html2 = re.sub(r'(?is)<script[^>]+src="\\/static\\/js\\/[pP]\\d{{6,8}}_\\d{{6}}[^"]*"[^>]*>\\s*<\\/script>', '', html)
      if html2 != html:
        resp.set_data(html2)
  except Exception:
    pass
  return resp
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] appended V2 sanitize on", appvar)
PY

python3 -m py_compile "$PYF" && echo "[OK] py_compile OK: $PYF"

echo "== restart 8910 =="
if [ -x bin/ui_restart_8910_no_restore_v1.sh ]; then
  bash bin/ui_restart_8910_no_restore_v1.sh
else
  pkill -f 'gunicorn .*8910' 2>/dev/null || true
  sleep 0.6
  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 120 --graceful-timeout 30 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    >/dev/null 2>&1 & disown || true
fi

echo "== quick verify HTML no stray P/p script tags =="
curl -sS http://127.0.0.1:8910/vsp4 | grep -nE '/static/js/[pP][0-9]{6,8}_[0-9]{6}' || echo "[OK] no stray P/p scripts in HTML"

echo "[NEXT] Ctrl+Shift+R rồi mở lại:"
echo "  http://127.0.0.1:8910/vsp4/#runs"
echo "  http://127.0.0.1:8910/vsp4/#datasource"
