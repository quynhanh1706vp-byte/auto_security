#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

S="bin/restart_8910_gunicorn_commercial_v5.sh"
[ -f "$S" ] || { echo "[ERR] missing $S"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$S" "$S.bak_force_wsgi_${TS}"
echo "[BACKUP] $S.bak_force_wsgi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p = Path("bin/restart_8910_gunicorn_commercial_v5.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

# force serve wsgi_vsp_ui_gateway:application
t2 = re.sub(r"wsgi_vsp_ui_gateway:(app|application)", "wsgi_vsp_ui_gateway:application", t)

# if not found at all, do nothing but warn
if t2 == t and "wsgi_vsp_ui_gateway:" not in t:
    print("[WARN] no wsgi_vsp_ui_gateway:<...> found in restart script; please grep it manually")
else:
    t = t2

p.write_text(t, encoding="utf-8")
print("[OK] patched restart script to force :application")
PY

chmod +x "$S"
echo "== grep wsgi target =="
grep -n "wsgi_vsp_ui_gateway:" -n "$S" || true

# hard reload: remove pycache so module definitely re-imports
rm -rf __pycache__ 2>/dev/null || true
rm -rf /home/test/Data/SECURITY_BUNDLE/ui/__pycache__ 2>/dev/null || true

rm -f out_ci/ui_8910.lock
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
