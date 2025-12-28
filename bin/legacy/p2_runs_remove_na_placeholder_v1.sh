#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

# candidate JS files for Runs tab
files=(
  static/js/vsp_runs_kpi_compact_v3.js
  static/js/vsp_runs_quick_actions_v1.js
  static/js/vsp_runs_reports_overlay_v1.js
  static/js/vsp_scan_panel_v1.js
)

TS="$(date +%Y%m%d_%H%M%S)"
changed=0

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  if grep -q 'N/A' "$f"; then
    cp -f "$f" "${f}.bak_na_${TS}"
    echo "[BACKUP] ${f}.bak_na_${TS}"
    python3 - "$f" <<'PY'
import sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8',errors='replace').read()
# Replace visible placeholders; keep internal tokens intact
s=s.replace("N/A", "—")
open(p,'w',encoding='utf-8').write(s)
print("[OK] patched", p)
PY
    node -c "$f"
    changed=$((changed+1))
  fi
done

echo "[OK] changed_files=$changed"
sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
