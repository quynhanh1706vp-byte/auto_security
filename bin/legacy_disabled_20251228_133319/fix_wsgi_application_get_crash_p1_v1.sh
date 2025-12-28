#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== stop 8910 =="
PID="$(cat out_ci/ui_8910.pid 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_appget_${TS}" && echo "[BACKUP] $F.bak_fix_appget_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

# detect Flask var name: <var> = Flask(...)
m=re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)
flask_var = m.group(1) if m else "app"

# patch only the findings_unified_v1 decorator line (root cause crash)
target = '@application.get("/api/vsp/findings_unified_v1/<rid>")'
if target in s:
  s = s.replace(target, f'@{flask_var}.route("/api/vsp/findings_unified_v1/<rid>", methods=["GET"])')
else:
  # fallback: if someone used single quotes
  s = s.replace("@application.get('/api/vsp/findings_unified_v1/<rid>')",
                f"@{flask_var}.route('/api/vsp/findings_unified_v1/<rid>', methods=['GET'])")

# also fix url_map checks inside that injected block (safe global replace)
s = s.replace("application.url_map.iter_rules()", f"{flask_var}.url_map.iter_rules()")

p.write_text(s, encoding="utf-8")
print("[OK] flask_var =", flask_var)
print("[OK] patched findings_unified_v1 decorator to attach on Flask app (not middleware)")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== start 8910 =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  >/dev/null 2>&1 &
sleep 0.9

echo "== probe =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8910/vsp4 || true

echo "== tail error log =="
tail -n 40 out_ci/ui_8910.error.log 2>/dev/null || true
