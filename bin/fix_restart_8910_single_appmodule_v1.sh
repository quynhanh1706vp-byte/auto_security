#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

S="bin/restart_8910_gunicorn_commercial_v5.sh"
[ -f "$S" ] || { echo "[ERR] missing $S"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$S" "$S.bak_single_appmodule_${TS}"
echo "[BACKUP] $S.bak_single_appmodule_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/restart_8910_gunicorn_commercial_v5.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

TARGET = "wsgi_vsp_ui_gateway_exportpdf_only:application"

# 1) Replace any existing APP_MODULE occurrences with TARGET
t = re.sub(r"\bwsgi_vsp_ui_gateway(?:(?:_exportpdf_only)?)\s*:\s*(?:app|application)\b", TARGET, t)
t = re.sub(r"\bvps?_demo_app\s*:\s*app\b", "", t)  # remove accidental second module
t = re.sub(r"\s{2,}", " ", t)

# 2) Ensure gunicorn command has exactly one APP_MODULE: keep the FIRST and drop any other ":app" tokens.
# Heuristic: if line contains 'gunicorn ' then keep options but enforce module right after gunicorn.
lines = t.splitlines()
out = []
for line in lines:
    if "gunicorn" in line:
        # remove any stray " <something>:app" occurrences except TARGET
        line2 = re.sub(r"\s+\S+:(?:app|application)\b", lambda m: (" "+TARGET) if TARGET in m.group(0) else "", line)
        # If TARGET not present, inject after gunicorn
        if TARGET not in line2:
            line2 = re.sub(r"\bgunicorn\b", f"gunicorn {TARGET}", line2, count=1)
        # If still multiple TARGET duplicates, collapse to one
        line2 = re.sub(rf"(?:\s+{re.escape(TARGET)})+", f" {TARGET}", line2)
        out.append(line2)
    else:
        out.append(line)

t2 = "\n".join(out) + "\n"
p.write_text(t2, encoding="utf-8")
print("[OK] restart script normalized to single APP_MODULE =", TARGET)
PY

chmod +x "$S"
echo "== gunicorn lines =="
grep -n "gunicorn" -n "$S" | head -n 20
