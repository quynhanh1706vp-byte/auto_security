#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56k2_fix_trace_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need find; need sort; need head; need sed; need awk

echo "== [P56K2] fix TRACE patterns + show context for remaining syntax fails ==" | tee "$EVID/summary.txt"

python3 - <<'PY' | tee -a "$EVID/summary.txt"
from pathlib import Path
import re, datetime

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
root = Path("static/js")
files = sorted(root.glob("*.js"))

# 1) info:"INFO", "TRACE"}  -> info:"INFO", trace:"TRACE"}
rx_trace_str = re.compile(r'(\binfo\s*:\s*"(?:INFO|Info)"\s*,)\s*"TRACE"\s*}')
# 2) ... INFO:2, 1}  -> ... INFO:2, TRACE:1}
rx_info_num_end = re.compile(r'(\bINFO\s*:\s*\d+\s*,)\s*(\d+)\s*}')
# 3) ... INFO:2, 1)  -> ... INFO:2, TRACE:1)
rx_info_num_par = re.compile(r'(\bINFO\s*:\s*\d+\s*,)\s*(\d+)\s*\)')
# 4) ... INFO:0, 0 } -> ... INFO:0, TRACE:0 }
rx_info_zero = re.compile(r'(\bINFO\s*:\s*0\s*,)\s*0(\s*[}\)])')

changed=[]
for f in files:
    s = f.read_text(encoding="utf-8", errors="replace")
    s2 = s
    s2 = rx_trace_str.sub(r'\1 trace:"TRACE"}', s2)
    s2 = rx_info_num_end.sub(r'\1 TRACE:\2}', s2)
    s2 = rx_info_num_par.sub(r'\1 TRACE:\2)', s2)
    s2 = rx_info_zero.sub(r'\1 TRACE:0\2', s2)

    if s2 != s:
        bak = f.with_suffix(f".js.bak_p56k2_{ts}")
        bak.write_text(s, encoding="utf-8", errors="ignore")
        f.write_text(s2, encoding="utf-8", errors="ignore")
        changed.append(f.name)

print("[CHANGED]", len(changed))
for x in changed[:200]:
    print(" -", x)
PY

echo "== [P56K2] node --check + context for fails ==" | tee -a "$EVID/summary.txt"

fails=0
while IFS= read -r f; do
  err="$EVID/$(basename "$f").err"
  if node --check "$f" >/dev/null 2>"$err"; then
    continue
  fi
  fails=$((fails+1))
  echo "" | tee -a "$EVID/summary.txt"
  echo "[FAIL] $f" | tee -a "$EVID/summary.txt"
  head -n 6 "$err" | tee -a "$EVID/summary.txt"

  # parse line number like: file.js:3646
  line="$(grep -Eo ':[0-9]+' "$err" | head -n 1 | tr -d ':' || true)"
  if [[ "${line:-}" =~ ^[0-9]+$ ]]; then
    start=$((line-12)); [ $start -lt 1 ] && start=1
    end=$((line+12))
    echo "--- context L${start}-L${end} ---" | tee -a "$EVID/summary.txt"
    nl -ba "$f" | sed -n "${start},${end}p" | tee -a "$EVID/summary.txt"
  fi
done < <(find static/js -maxdepth 1 -type f -name '*.js' | sort)

echo "" | tee -a "$EVID/summary.txt"
echo "fails=$fails" | tee -a "$EVID/summary.txt"
echo "[DONE] Evidence=$EVID" | tee -a "$EVID/summary.txt"
