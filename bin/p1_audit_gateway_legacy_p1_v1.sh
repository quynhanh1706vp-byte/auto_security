#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need date; need grep; need python3

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/audit_legacy_${TS}"
mkdir -p "$OUT"

echo "[INFO] writing: $OUT"

# list all markers
grep -n "VSP_" "$F" | tee "$OUT/all_markers.txt" || true

# focus legacy candidates
grep -nE "NETGUARD|V6B?|after_request|contract attempt|RUNS_500_FALLBACK|cache_cap|degraded_panel" "$F" \
  | tee "$OUT/legacy_candidates.txt" || true

python3 - <<'PY'
from pathlib import Path
import re
f=Path("wsgi_vsp_ui_gateway.py")
s=f.read_text(encoding="utf-8", errors="replace")
keep=[
"VSP_P0_PROBE_NONFLAKE_V2",
"VSP_P1_RUNS_CONTRACT_WSGIMW_V2",
"VSP_P0_PIN_RUNS_ROOT_PREFER_REAL_V1",
"VSP_P1_SHA256_ALWAYS200_WSGIMW_V2",
]
marks=sorted(set(re.findall(r'VSP_[A-Z0-9_]{6,}', s)))
print("[MARKERS] total:", len(marks))
print("[KEEP]   :", keep)
extra=[m for m in marks if m not in keep]
print("[EXTRA]  :", len(extra))
for m in extra[:200]:
    print(" -", m)
PY | tee "$OUT/marker_summary.txt"

echo "[OK] audit done: $OUT"
