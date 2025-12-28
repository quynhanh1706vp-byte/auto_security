#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS (JS step chưa tạo?)"; exit 2; }

python3 - <<PY
from pathlib import Path
import time

ts="${TS}"
marker="VSP_P1_GATE_STORY_PANEL_V1"
script_line = '<script src="/static/js/vsp_dashboard_gate_story_v1.js?v={{ asset_v }}"></script> <!-- VSP_P1_GATE_STORY_PANEL_V1 -->'

tpls = [
  Path("templates/vsp_5tabs_enterprise_v2.html"),
  Path("templates/vsp_dashboard_2025.html"),
]

for p in tpls:
    if not p.exists():
        print("[WARN] missing:", p)
        continue

    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s or "vsp_dashboard_gate_story_v1.js" in s:
        print("[OK] already injected:", p)
        continue

    bak = p.with_name(p.name + f".bak_gate_story_injectfix_{ts}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak)

    if "</body>" in s:
        s2 = s.replace("</body>", script_line + "\n</body>")
    else:
        s2 = s + "\n" + script_line + "\n"

    p.write_text(s2, encoding="utf-8")
    print("[OK] injected:", p)
PY

# restart chuẩn của bạn
bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" | head -n 3 || true
curl -fsS "$BASE/api/vsp/runs?limit=1" | head -c 220; echo
echo "[DONE] inject fix applied."
