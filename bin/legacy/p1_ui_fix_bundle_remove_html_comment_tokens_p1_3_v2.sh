#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_rm_htmlcomment_${TS}"
echo "[BACKUP] ${F}.bak_rm_htmlcomment_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

# Remove pure HTML-comment lines (these can break Node parsing if they end up outside a string)
lines = s.splitlines(True)
out = []
removed = 0
for ln in lines:
    if re.match(r'^\s*<!--.*-->\s*$', ln):
        removed += 1
        continue
    out.append(ln)

p.write_text("".join(out) + ("\n" if not out or not out[-1].endswith("\n") else ""), encoding="utf-8")
print(f"[OK] removed html-comment lines: {removed}")
PY

if command -v node >/dev/null 2>&1; then
  echo "== node --check $F =="
  node --check "$F"
  echo "[OK] JS parse OK"
else
  echo "[WARN] node not installed; skip parse check"
fi
