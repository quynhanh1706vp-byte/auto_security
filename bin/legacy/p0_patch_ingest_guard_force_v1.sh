#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p0_data_first_ingest_latest_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_guard_${TS}"
echo "[BACKUP] $F.bak_guard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p0_data_first_ingest_latest_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P0_INGEST_GUARD_FORCE_V1" in s:
    print("[OK] guard already present")
    raise SystemExit(0)

# inject FORCE and skip-if-already-built just before python3 build block
marker = "python3 - <<PY"
idx = s.find(marker)
if idx < 0:
    raise SystemExit("[ERR] cannot find python3 heredoc marker")

inject = r'''
# --- VSP_P0_INGEST_GUARD_FORCE_V1 ---
FORCE="${FORCE:-0}"
if [ "${FORCE}" != "1" ] && [ -f "$DST/reports/findings_unified.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    GEN="$(jq -r '.meta.generated_at // empty' "$DST/reports/findings_unified.json" 2>/dev/null || true)"
    TOT="$(jq -r '.meta.items_total // empty' "$DST/reports/findings_unified.json" 2>/dev/null || true)"
    if [ -n "$GEN" ] && [ -n "$TOT" ]; then
      echo "[SKIP] unified already built (generated_at=$GEN items_total=$TOT). Set FORCE=1 to rebuild."
      echo "[INFO] verify export_csv size for rid=$ALIAS"
      curl -sS -I "$BASE/api/vsp/export_csv?rid=$ALIAS" | egrep -i 'HTTP/|Content-Length|Content-Disposition' || true
      exit 0
    fi
  fi
fi
# --- /VSP_P0_INGEST_GUARD_FORCE_V1 ---

'''
s2 = s[:idx] + inject + s[idx:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected guard: VSP_P0_INGEST_GUARD_FORCE_V1")
PY
