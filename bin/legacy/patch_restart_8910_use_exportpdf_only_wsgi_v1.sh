#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

S="bin/restart_8910_gunicorn_commercial_v5.sh"
[ -f "$S" ] || { echo "[ERR] missing $S"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$S" "$S.bak_use_exportpdf_only_${TS}"
echo "[BACKUP] $S.bak_use_exportpdf_only_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p = Path("bin/restart_8910_gunicorn_commercial_v5.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

# replace any wsgi target to the new entry
t2 = re.sub(r"wsgi_vsp_ui_gateway:[a-zA-Z_]+", "wsgi_vsp_ui_gateway_exportpdf_only:application", t)
if t2 == t and "wsgi_vsp_ui_gateway_exportpdf_only:application" not in t:
    # if not found, append as a safety note (but usually it exists)
    t2 = t.replace("gunicorn ", "gunicorn wsgi_vsp_ui_gateway_exportpdf_only:application ")

p.write_text(t2, encoding="utf-8")
print("[OK] forced gunicorn target: wsgi_vsp_ui_gateway_exportpdf_only:application")
PY

chmod +x "$S"

rm -f out_ci/ui_8910.lock
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
