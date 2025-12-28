#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_runs_kpi_compact_v3.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_rawv3_${TS}"
echo "[BACKUP] ${JS}.bak_rawv3_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_RUNS_USE_RAW_V3_LINKS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

s = s.replace("/api/vsp/run_file_raw_v2", "/api/vsp/run_file_raw_v3")
p.write_text(s + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] replaced raw v2 -> raw v3")
PY

node -c "$JS"
echo "[OK] node -c OK"
sudo systemctl restart "$SVC" || true
echo "[OK] restarted (if service exists)"
grep -n "VSP_P2_RUNS_USE_RAW_V3_LINKS_V1" "$JS" | tail -n 2 || true
