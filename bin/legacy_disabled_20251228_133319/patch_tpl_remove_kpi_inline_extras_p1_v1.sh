#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_rm_kpi_inline_${TS}" && echo "[BACKUP] $T.bak_rm_kpi_inline_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
t=Path("templates/vsp_4tabs_commercial_v1.html")
s=t.read_text(encoding="utf-8", errors="ignore")
# remove the injected block by marker
s2=re.sub(r'(?s)\s*<!--\s*===\s*VSP_TPL_KPI_INLINE_EXTRAS_P1_V1\s*===\s*-->.*?</script>\s*','\n',s, count=1)
t.write_text(s2, encoding="utf-8")
print("[OK] removed VSP_TPL_KPI_INLINE_EXTRAS_P1_V1 (best-effort)")
PY
