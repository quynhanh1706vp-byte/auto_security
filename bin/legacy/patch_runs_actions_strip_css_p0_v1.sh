#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
CSS="static/css/vsp_2025_dark.css"
[ -f "$CSS" ] || { echo "[ERR] missing $CSS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$CSS" "${CSS}.bak_strip_${TS}"
echo "[BACKUP] ${CSS}.bak_strip_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/css/vsp_2025_dark.css")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUNS_ACTIONS_STRIP_CSS_P0_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon = r"""
/* VSP_RUNS_ACTIONS_STRIP_CSS_P0_V1 */
.vsp-actions-strip{
  display:inline-flex;
  align-items:center;
  gap:6px;
  flex-wrap:wrap;
}
.vsp-actions-strip .btn.btn-sm{
  padding:2px 8px;
  line-height:18px;
  font-size:12px;
  border-radius:10px;
}
"""
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] wrote:", p)
PY

sudo systemctl restart vsp-ui-8910.service
