#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

TPL="templates/vsp_dashboard_2025.html"
JS="static/js/vsp_tools_status_from_gate_p0_v1.js"

echo "== [1/3] disable tools_status script tag in template =="
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_disable_tools_status_${TS}" && echo "[BACKUP] $TPL.bak_disable_tools_status_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("templates/vsp_dashboard_2025.html")
s=p.read_text(encoding="utf-8", errors="ignore")
pat=re.compile(r'(<script[^>]+src=["\'][^"\']*vsp_tools_status_from_gate_p0_v1\.js[^"\']*["\'][^>]*>\s*</script>)', re.I)
s2,n=pat.subn(r'<!-- DISABLED_P0: \1 -->', s)
p.write_text(s2, encoding="utf-8")
print("[OK] disabled tools_status tags =", n)
PY

echo "== [2/3] replace tools_status JS with SAFE stub (no parse error) =="
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "$JS.bak_stub_${TS}" && echo "[BACKUP] $JS.bak_stub_${TS}"

cat > "$JS" <<'JS'
/* VSP_TOOLS_STATUS_STUB_P0_V1: disabled to stabilize UI (broken upstream file caused parse errors) */
(function(){
  'use strict';
  try{
    console.warn('[VSP_TOOLS_STATUS_STUB_P0_V1] tools_status disabled (P0 stabilize).');
  }catch(_){}
})();
JS

node --check "$JS" >/dev/null && echo "[OK] node --check tools_status stub" || { echo "[ERR] stub syntax failed"; exit 3; }

echo "== [3/3] done. Restart UI + Ctrl+Shift+R + Ctrl+0 =="
