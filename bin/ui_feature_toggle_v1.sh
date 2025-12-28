#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

FEAT="${1:-}"
MODE="${2:-on}"
F="static/js/vsp_ui_features_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F (run patch_ui_route_scoped_loader_safe_v1.sh first)"; exit 2; }

case "$FEAT" in
  dashboard) KEY="DASHBOARD_CHARTS"; FILES=("static/js/vsp_dashboard_enhance_v1.js" "static/js/vsp_dashboard_charts_pretty_v3.js" "static/js/vsp_degraded_panel_hook_v3.js");;
  runs) KEY="RUNS_PANEL"; FILES=("static/js/vsp_runs_tab_resolved_v1.js");;
  datasource) KEY="DATASOURCE_TAB"; FILES=("static/js/vsp_datasource_tab_v1.js");;
  settings) KEY="SETTINGS_TAB"; FILES=("static/js/vsp_settings_tab_v1.js");;
  rules) KEY="RULE_OVERRIDES_TAB"; FILES=("static/js/vsp_rule_overrides_tab_v1.js");;
  *) echo "[USAGE] $0 {dashboard|runs|datasource|settings|rules} {on|off}"; exit 2;;
esac

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_toggle_${TS}"
echo "[BACKUP] $F.bak_toggle_${TS}"

python3 - <<PY
from pathlib import Path
import re
p=Path("$F")
s=p.read_text(encoding="utf-8", errors="ignore")

# set KEY to true/false inside window.__VSP_FEATURE_FLAGS__
key="$KEY"
val = "true" if "$MODE"=="on" else "false"

# replace "KEY: false/true" safely
pat = r'(%s\\s*:\\s*)(true|false)' % re.escape(key)
ns, n = re.subn(pat, r'\\g<1>' + val, s)
if n==0:
  raise SystemExit(f"[ERR] cannot find key to toggle: {key}")
p.write_text(ns, encoding="utf-8")
print(f"[OK] {key} => {val}")
PY

# syntax check modules (if exist)
BAD=0
for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    if ! node --check "$f" >/dev/null 2>&1; then
      echo "[ERR] syntax invalid: $f"
      BAD=1
    else
      echo "[OK] node --check: $f"
    fi
  else
    echo "[WARN] missing module file (skip): $f"
  fi
done

if [ "$BAD" = "1" ]; then
  echo "[ROLLBACK] restore features file"
  cp -f "$F.bak_toggle_${TS}" "$F"
  exit 3
fi

echo "[NEXT] Ctrl+Shift+R then open route: #$FEAT (dashboard uses #dashboard)"
