#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
B="static/js/vsp_bundle_commercial_v2.js"
G="static/js/vsp_dashboard_gate_story_v1.js"

[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_ridredir_${TS}"
echo "[BACKUP] ${B}.bak_ridredir_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
old = "/api/vsp/rid_latest"
new = "/api/vsp/rid_latest_gate_root"
n = s.count(old)
if n == 0:
    print("[WARN] no /api/vsp/rid_latest found in bundle (maybe already patched or different string)")
else:
    s = s.replace(old, new)
    p.write_text(s, encoding="utf-8")
    print("[OK] replaced in bundle:", n)
PY

# (optional) fix your GateStory url typo if it exists (gate_root_gate_root)
if [ -f "$G" ]; then
  cp -f "$G" "${G}.bak_ridredir_${TS}" || true
  python3 - <<'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
if not p.exists():
    raise SystemExit(0)
s = p.read_text(encoding="utf-8", errors="replace")
s2 = s.replace("/api/vsp/rid_latest_gate_root_gate_root_v1","/api/vsp/rid_latest_gate_root_v1") \
      .replace("/api/vsp/rid_latest_gate_root_gate_root","/api/vsp/rid_latest_gate_root")
if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] fixed GateStory double gate_root typo")
else:
    print("[OK] GateStory no double gate_root typo")
PY
fi

echo "== smoke: rid_latest_gate_root must return rid =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 220; echo

echo "== smoke: /vsp5 includes scripts =="
curl -fsS "$BASE/vsp5" | egrep -n "vsp_bundle_commercial_v2|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" | head -n 60

echo "[DONE] Now do Ctrl+Shift+R on /vsp5 (hard reload) to clear cached JS."
