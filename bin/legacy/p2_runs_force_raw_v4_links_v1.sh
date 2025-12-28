#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_kpi_compact_v3.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_force_rawv4_${TS}"
echo "[BACKUP] ${JS}.bak_force_rawv4_${TS}"

python3 - "$JS" <<'PY'
import re, sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_RUNS_FORCE_RAW_V4_LINKS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

s2=re.sub(r"/api/vsp/run_file_raw_v\d+", "/api/vsp/run_file_raw_v4", s)
p.write_text(s2 + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] forced all run_file_raw_v* -> v4")
PY

node -c "$JS"
echo "[OK] node -c OK"
sudo systemctl restart "$SVC" || true
echo "[OK] restarted (if service exists)"
