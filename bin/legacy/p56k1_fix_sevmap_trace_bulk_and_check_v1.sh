#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56k1_fix_sev_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need find; need sort; need wc; need head; need cp

echo "== [P56K1] Fix sev-map TRACE bulk + node --check ==" | tee "$EVID/summary.txt"

python3 - <<'PY'
from pathlib import Path
import re, datetime

root = Path("static/js")
files = sorted(root.glob("*.js"))
pat1 = re.compile(r'(\bconst\s+sev\s*=\s*\{[^}]*\bINFO\s*:\s*0\s*,)\s*0\s*(\})', re.S)
pat2 = re.compile(r'(\bINFO\s*:\s*0\s*,)\s*0\s*(\})')  # looser
changed=[]
for f in files:
    s = f.read_text(encoding="utf-8", errors="replace")
    s2 = pat1.sub(r'\1 TRACE:0\2', s)
    s2 = pat2.sub(r'\1 TRACE:0\2', s2)
    # also fix "{..., INFO:0,0}" variants
    s2 = re.sub(r'(\bINFO\s*:\s*0\s*,)\s*0\s*(?=\s*[,}])', r'\1 TRACE:0', s2)
    if s2 != s:
        bak = f.with_suffix(f.suffix + ".bak_p56k1_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
        bak.write_text(s, encoding="utf-8", errors="ignore")
        f.write_text(s2, encoding="utf-8", errors="ignore")
        changed.append(f.as_posix())
print("[CHANGED]", len(changed))
for x in changed[:200]:
    print(" -", x)
PY | tee -a "$EVID/summary.txt"

echo "== [P56K1] node --check all static/js/*.js (informational) ==" | tee -a "$EVID/summary.txt"
fails=0
while IFS= read -r f; do
  if ! node --check "$f" >/dev/null 2>"$EVID/$(basename "$f").err"; then
    echo "[FAIL] $f" | tee -a "$EVID/summary.txt"
    head -n 2 "$EVID/$(basename "$f").err" | tee -a "$EVID/summary.txt"
    fails=$((fails+1))
  fi
done < <(find static/js -maxdepth 1 -type f -name '*.js' | sort)

echo "fails=$fails" | tee -a "$EVID/summary.txt"
echo "[DONE] Evidence=$EVID"
