#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_data_source_tab_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_runsv2_${TS}"
echo "[BACKUP] ${JS}.bak_runsv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_data_source_tab_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")

# replace only exact legacy runs endpoint
s2, n1 = re.subn(r'(["\'])/api/ui/runs(\?|\1)', r'\1/api/ui/runs_v2\2', s)
# also handle template string /api/ui/runs?limit=...
s2, n2 = re.subn(r'(/api/ui/runs)(\?)', r'/api/ui/runs_v2\2', s2)

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p, "replacements=", (n1+n2))
PY

echo "== quick grep endpoints =="
grep -n "/api/ui/runs" -n "$JS" || true
grep -n "/api/ui/runs_v2" -n "$JS" || true

echo "== verify endpoint works =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/ui/runs_v2?limit=1" | head -c 180; echo
echo "[OK] done"
