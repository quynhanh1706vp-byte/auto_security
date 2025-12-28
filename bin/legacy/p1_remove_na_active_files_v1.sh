#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need find; need grep; need head

TS="$(date +%Y%m%d_%H%M%S)"
echo "== [1] collect active files containing word-boundary N/A =="
LIST="/tmp/vsp_na_files_${TS}.txt"
: > "$LIST"

# only patch presentation layers by default
find static templates -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' \) \
  ! -name '*.bak_*' ! -name '*.broken_*' ! -name '*.disabled_*' -print0 \
| xargs -0 grep -nH -E '\bN/A\b' 2>/dev/null \
| awk -F: '{print $1}' | sort -u > "$LIST" || true

if [ ! -s "$LIST" ]; then
  echo "[OK] no active files contain word-boundary N/A"
  exit 0
fi

echo "[INFO] files to patch:"
cat "$LIST" | sed 's/^/  - /'
echo

echo "== [2] patch (backup + replace) =="
python3 - "$LIST" "$TS" <<'PY'
import sys, shutil
from pathlib import Path

lst=Path(sys.argv[1]).read_text().splitlines()
ts=sys.argv[2]

changed=0
for f in lst:
    p=Path(f)
    if not p.exists(): 
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    if "N/A" not in s:
        continue
    b = p.with_suffix(p.suffix + f".bak_na_{ts}")
    shutil.copy2(p, b)
    # Replace exact token N/A -> —
    p.write_text(s.replace("N/A", "—"), encoding="utf-8")
    changed += 1
print(f"[OK] patched_files={changed}")
PY

echo "== [3] verify no active N/A left =="
find static templates -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' \) \
  ! -name '*.bak_*' ! -name '*.broken_*' ! -name '*.disabled_*' -print0 \
| xargs -0 grep -nH -E '\bN/A\b' 2>/dev/null \
| head -n 40 || echo "[OK] clean: no active N/A"
