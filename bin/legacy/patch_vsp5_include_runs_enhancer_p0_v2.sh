#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need grep; need sed; need date; need curl

PYF="$(grep -RIl --exclude='*.bak*' --exclude-dir='out_ci' --exclude-dir='out' "/vsp5" . | grep -E '\.py$' | head -n1 || true)"
[ -n "$PYF" ] || { echo "[ERR] cannot find /vsp5 route in .py"; exit 2; }
echo "[ROUTE_PY]=$PYF"

TPL="$(python3 - <<PY
import re
from pathlib import Path
s=Path("$PYF").read_text(encoding="utf-8", errors="replace")
# try capture render_template("xxx.html") in the /vsp5 route function
m=re.search(r"@.*route\\(\\s*['\\\"]/vsp5['\\\"]\\s*\\)[\\s\\S]{0,800}?render_template\\(\\s*['\\\"]([^'\\\"]+\\.html)['\\\"]", s)
if not m:
  m=re.search(r"@.*get\\(\\s*['\\\"]/vsp5['\\\"]\\s*\\)[\\s\\S]{0,800}?render_template\\(\\s*['\\\"]([^'\\\"]+\\.html)['\\\"]", s)
print(m.group(1) if m else "")
PY
)"
[ -n "$TPL" ] || { echo "[ERR] cannot extract template from $PYF for /vsp5"; exit 3; }

TP="templates/$TPL"
[ -f "$TP" ] || { echo "[ERR] template not found: $TP"; exit 4; }
echo "[TPL]=$TP"

JS="/static/js/vsp_runs_tab_resolved_v1.js"
[ -f "static/js/vsp_runs_tab_resolved_v1.js" ] || { echo "[ERR] missing static/js/vsp_runs_tab_resolved_v1.js"; exit 5; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TP" "${TP}.bak_include_runs_enh_${TS}"
echo "[BACKUP] ${TP}.bak_include_runs_enh_${TS}"

MARK="VSP5_INCLUDE_RUNS_ENHANCER_P0_V2"
if grep -q "$MARK" "$TP"; then
  echo "[OK] marker already present"
else
  # inject before </body>
  sed -i "s#</body>#\n<!-- ${MARK} -->\n<script defer src=\"${JS}?v=${TS}\"></script>\n</body>#I" "$TP"
  echo "[OK] injected script into $TP"
fi

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== verify /vsp5 includes runs js =="
HTML="$(curl -sS http://127.0.0.1:8910/vsp5 || true)"
echo "$HTML" | grep -q "vsp_runs_tab_resolved_v1.js" && echo "[OK] script present in /vsp5 HTML" || {
  echo "[FAIL] /vsp5 HTML does NOT include vsp_runs_tab_resolved_v1.js"
  echo "$HTML" | grep -oE '/static/js/[^"]+' | sort -u | sed -n '1,200p'
  exit 6
}

echo "== list js loaded by /vsp5 (for sanity) =="
echo "$HTML" | grep -oE '/static/js/[^"]+' | sort -u | sed -n '1,200p'
