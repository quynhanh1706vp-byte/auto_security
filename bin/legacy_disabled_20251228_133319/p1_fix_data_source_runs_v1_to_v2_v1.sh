#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_data_source_tab_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_runsfix_${TS}"
echo "[BACKUP] ${JS}.bak_runsfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_data_source_tab_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")
s2, n = re.subn(r'(/api/ui/runs)_v1', r'\1_v2', s)
if n == 0:
    # fallback: đôi khi viết cứng "runs_v1" không có "_v1" pattern
    s2, n2 = re.subn(r'api/ui/runs_v1', 'api/ui/runs_v2', s)
    n += n2
p.write_text(s2, encoding="utf-8")
print("[OK] replacements=", n)
PY

echo "== grep runs_* in file =="
grep -n "api/ui/runs" "$JS" || true

echo "== verify endpoint =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/ui/runs_v2?limit=2" | head -c 220; echo

# guard: không còn runs_v1
if grep -q "runs_v1" "$JS"; then
  echo "[ERR] still contains runs_v1 in $JS"
  exit 2
fi
echo "[DONE] Data Source should stop 404. Now hard-refresh browser."
