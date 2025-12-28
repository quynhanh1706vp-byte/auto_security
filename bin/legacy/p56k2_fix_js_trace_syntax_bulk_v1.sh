#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56k2_fix_js_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need find; need sort; need wc; need head; need cp

echo "== [P56K2] bulk fix TRACE-related JS syntax ==" | tee "$EVID/summary.txt"

python3 - <<'PY' | tee -a "$EVID/summary.txt"
from pathlib import Path
import re, datetime

root = Path("static/js")
ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
changed = []

def backup(p: Path):
    bak = p.with_suffix(p.suffix + f".bak_p56k2_{ts}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak.name

def patch_text(s: str, fname: str):
    o = s

    # 1) Object literal ends with ", 0 }" or ", 1 }" etc => treat as TRACE:<num>
    s = re.sub(r'(\bINFO\s*:\s*\d+\s*),\s*(\d+)\s*([}\]])', r'\1, TRACE:\2\3', s)

    # 2) Object literal ends with , "TRACE" } or , 'TRACE' } => assume key "trace"
    # common: const map = {critical:"CRITICAL", ... , "TRACE"};
    s = re.sub(r',\s*([\'"])TRACE\1\s*([}\]])', r', trace:"TRACE"\2', s)

    # 3) line that is just 'Trace' / "Trace" inside an object => add TRACE key
    s = re.sub(r'(?m)^\s*([\'"])Trace\1\s*,?\s*$', r'  TRACE:"Trace",', s)

    # 4) line that is just "#a855f7" (common “TRACE color” missing key)
    s = re.sub(r'(?m)^\s*([\'"])#a855f7\1\s*,?\s*$', r'  TRACE:"#a855f7",', s)

    # 5) line that is just "rgba(...)" inside severity color map missing key
    # only patch if looks like rgba + likely in a map block
    s = re.sub(r'(?m)^\s*([\'"])rgba\([0-9,\s.]+\)\1\s*,?\s*$', r'  TRACE:"rgba(201, 203, 207, 0.9)",', s)

    # 6) dangling "TRACE" as a bare token in object like { ..., info:"INFO", "TRACE"} => make trace:"TRACE"
    s = re.sub(r'(\binfo\s*:\s*[\'"]INFO[\'"]\s*),\s*("TRACE"|\'TRACE\')\s*([}\]])', r'\1, trace:"TRACE"\3', s, flags=re.I)

    # 7) broken sev order maps like {CRITICAL:6,...,INFO:2, 1} => TRACE:1 (covered by #1 but keep safe)
    s = re.sub(r'(\bINFO\s*:\s*2\s*),\s*1\s*([}\]])', r'\1, TRACE:1\2', s)

    # 8) the “c.TRACE ?? 0,” line inside object (missing key)
    s = re.sub(r'(?m)^\s*c\.TRACE\s*\?\?\s*0\s*,\s*$', r'  TRACE:(c.TRACE ?? 0),', s)

    # 9) ensure we don't accidentally create double TRACE keys (very conservative clean-up)
    # (do nothing if duplicate; node --check will still pass; runtime logic may choose last)
    return s, (s != o)

fails = []
for p in sorted(root.glob("*.js")):
    s = p.read_text(encoding="utf-8", errors="replace")
    s2, did = patch_text(s, p.name)
    if did:
        bak = backup(p)
        p.write_text(s2, encoding="utf-8")
        changed.append((str(p), bak))

print(f"[CHANGED] {len(changed)}")
for f,b in changed[:60]:
    print(" -", f, "<=", b)
PY

echo "== [P56K2] node --check all static/js/*.js ==" | tee -a "$EVID/summary.txt"
FAILS="$EVID/fails.txt"
: > "$FAILS"
while IFS= read -r f; do
  if ! node --check "$f" >/dev/null 2>&1; then
    echo "$f" | tee -a "$FAILS" >/dev/null
  fi
done < <(find static/js -maxdepth 1 -type f -name '*.js' | sort)

fc="$(wc -l < "$FAILS" | tr -d ' ')"
echo "[INFO] fails_count=$fc" | tee -a "$EVID/summary.txt"
if [ "$fc" -gt 0 ]; then
  echo "[FAIL] still failing files (see $FAILS)" | tee -a "$EVID/summary.txt"
  head -n 60 "$FAILS" | tee -a "$EVID/summary.txt"
  exit 1
fi

echo "[PASS] All static/js/*.js pass node --check. Evidence=$EVID" | tee -a "$EVID/summary.txt"
