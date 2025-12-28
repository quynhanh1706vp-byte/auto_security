#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need find; need grep; need sort

TS="$(date +%Y%m%d_%H%M%S)"
LIST="/tmp/vsp_na_fixed_${TS}.txt"
: > "$LIST"

# gather files containing literal N/A (exclude backups)
find static templates -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' \) \
  ! -name '*.bak_*' ! -name '*.broken_*' ! -name '*.disabled_*' -print0 \
| xargs -0 grep -l -F "N/A" 2>/dev/null \
| sort -u > "$LIST" || true

if [ ! -s "$LIST" ]; then
  echo "[OK] no files need patch (no literal N/A found)"
  exit 0
fi

echo "[INFO] patching files:"
sed 's/^/  - /' "$LIST"

python3 - "$LIST" "$TS" <<'PY'
import sys, shutil
from pathlib import Path
lst=Path(sys.argv[1]).read_text().splitlines()
ts=sys.argv[2]
n=0
for f in lst:
    p=Path(f)
    s=p.read_text(encoding="utf-8", errors="replace")
    if "N/A" not in s: 
        continue
    b=p.with_suffix(p.suffix+f".bak_nafixed_{ts}")
    shutil.copy2(p,b)
    p.write_text(s.replace("N/A","—"), encoding="utf-8")
    n+=1
print("[OK] patched_files=", n)
PY

echo "== verify =="
bash bin/p1_repo_scan_na_fixed_v1.sh
