#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need sed

TS="$(date +%Y%m%d_%H%M%S)"
FILES=(
  "static/js/vsp_bundle_tabs5_v1.js"
  "static/js/vsp_tabs4_autorid_v1.js"
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "${f}.bak_fixbsn_${TS}"
  echo "[OK] backup: ${f}.bak_fixbsn_${TS}"

  python3 - <<PY
from pathlib import Path
import re

p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")

# remove BOM/zero-width again (safe)
s=s.replace("\ufeff","")
for ch in ["\u200b","\u200c","\u200d","\u2060","\u180e"]:
    s=s.replace(ch,"")

# KEY FIX: drop literal backslash escapes at end-of-line:  \n  \r  \t
lines=s.splitlines(True)
out=[]
for ln in lines:
    # remove \\n/\\r/\\t ONLY if it is trailing on the line (outside strings doesn't matter here)
    out.append(re.sub(r'\\\\[nrt]\\s*(?=\\r?\\n$|$)', '', ln))
s="".join(out)

# also handle common exact pattern that caused your error
s=s.replace("})();\\\\n", "})();\n")

p.write_text(s, encoding="utf-8")
print("[OK] fixed trailing \\\\n/\\\\r/\\\\t in", p)
PY

  if node --check "$f" >/dev/null 2>&1; then
    echo "[OK] node --check PASS: $f"
  else
    echo "[ERR] still FAIL: $f"
    node --check "$f" 2>&1 | sed -n '1,12p'
    exit 3
  fi
done

echo "[DONE] Hard refresh: http://127.0.0.1:8910/vsp5  (Ctrl+Shift+R)"
