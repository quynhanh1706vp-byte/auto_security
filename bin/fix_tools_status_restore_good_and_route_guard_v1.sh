#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

JS="static/js/vsp_tools_status_from_gate_p0_v1.js"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "== [1/5] pick latest GOOD backup that passes node --check =="
CANDS="$(ls -1t ${JS}.bak_* 2>/dev/null || true)"
GOOD=""
for b in $CANDS; do
  if node --check "$b" >/dev/null 2>&1; then
    GOOD="$b"
    break
  fi
done
[ -n "${GOOD:-}" ] || { echo "[ERR] no good backup found for $JS"; echo "$CANDS"; exit 3; }
echo "[OK] GOOD=$GOOD"

echo "== [2/5] restore to GOOD backup =="
cp -f "$JS" "${JS}.bak_before_restore_${TS}" && echo "[BACKUP] ${JS}.bak_before_restore_${TS}"
cp -f "$GOOD" "$JS" && echo "[RESTORE] $JS <= $GOOD"

echo "== [3/5] wrap route-guard (only run on #runs) =="
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_tools_status_from_gate_p0_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")
if "VSP_TOOLS_STATUS_ROUTE_GUARD_P0_V1" in s:
    print("[OK] already guarded")
    raise SystemExit(0)

head = """/* VSP_TOOLS_STATUS_ROUTE_GUARD_P0_V1 */
(function(){
  'use strict';
  function __vsp_is_runs(){
    try{
      const h=(location.hash||'').toLowerCase();
      return h.startsWith('#runs') || h.includes('#runs/');
    }catch(e){ return false; }
  }
  if(!__vsp_is_runs()){
    try{ console.info('[VSP_TOOLS_STATUS_ROUTE_GUARD_P0_V1] skip on', location.hash); }catch(_){}
    return;
  }

"""
tail = "\n})();\n"
p.write_text(head + s + tail, encoding="utf-8")
print("[OK] guarded tools_status file")
PY

echo "== [4/5] node syntax check =="
node --check "$JS" >/dev/null && echo "[OK] node --check tools_status" || { echo "[ERR] still broken"; node --check "$JS"; exit 4; }

echo "== [5/5] cachebust template to force reload =="
if [ -f "$TPL" ]; then
  cp -f "$TPL" "$TPL.bak_cb_tools_${TS}" && echo "[BACKUP] $TPL.bak_cb_tools_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$TPL")
s=p.read_text(encoding="utf-8", errors="ignore")
s=re.sub(r'(vsp_tools_status_from_gate_p0_v1\.js)(\?[^"\']*)?', r'\1?v=$TS', s)
p.write_text(s, encoding="utf-8")
print("[OK] cachebusted tools_status in template")
PY
else
  echo "[WARN] missing $TPL, skip cachebust"
fi

echo "[DONE] restart UI + Ctrl+Shift+R + Ctrl+0"
