#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_SAFE_DRILLDOWN_HARDEN_P0_V6"

# tìm mọi file có callsite lỗi
mapfile -t FILES < <(grep -RIl --exclude='*.bak*' "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" static/js 2>/dev/null | sort -u)
echo "[OK] found ${#FILES[@]} JS callsites"
for F in "${FILES[@]}"; do
  [ -f "$F" ] || continue
  cp -f "$F" "$F.bak_${MARK}_${TS}" && echo "[BACKUP] $F.bak_${MARK}_${TS}"
  python3 - "$F" "$MARK" <<'PY'
from pathlib import Path, re, sys
p=Path(sys.argv[1]); mark=sys.argv[2]
s=p.read_text(encoding='utf-8', errors='replace')
if mark in s: raise SystemExit
pat=r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
rep=f"(typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==='function'?VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:()=>console.debug('[SAFE_SKIP drilldown]'))("
ns=re.sub(pat,rep,s)
p.write_text("// "+mark+"\n"+ns,encoding='utf-8')
print('[OK] patched',p)
PY
  node --check "$F" && echo "[OK] syntax:", "$F"
done
echo "DONE. Ctrl+Shift+R và mở #dashboard để confirm hết TypeError."
