#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need node; need date

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rm_vsp4ref_${TS}"
echo "[BACKUP] ${F}.bak_rm_vsp4ref_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# Remove only the literal token references (keep it minimal, avoid breaking logic)
s = s.replace("vsp_4tabs_commercial_v1", "vsp_5tabs_enterprise_v2")
s = s.replace("vsp_ui_4tabs_commercial_v1", "vsp_bundle_commercial_v2")

if s == orig:
    print("[WARN] no change (token not found).")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] replaced tokens in vsp_dashboard_enhance_v1.js")
PY

echo "== GATE: node --check =="
node --check static/js/vsp_dashboard_enhance_v1.js >/dev/null
echo "[OK] node --check OK"

echo "== CHECK: grep vsp4 tokens (scope-limited) =="
grep -RIn --exclude='*.bak_*' "vsp_4tabs_commercial_v1\|vsp_ui_4tabs_commercial_v1\|/vsp4" templates static/js 2>/dev/null || true

echo "[DONE]"
