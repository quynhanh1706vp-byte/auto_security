#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p31_cache_vsp5_html_shell_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_smokefix_${TS}"
echo "[BACKUP] ${F}.bak_smokefix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p31_cache_vsp5_html_shell_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the smoke section entirely (from 'echo "== [SMOKE]' to end) robustly
m=re.search(r'echo "== \[SMOKE\].*', s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate SMOKE block")

prefix=s[:m.start()]
smoke=r'''echo "== [SMOKE] /vsp5 cache header + time =="
BASE="${BASE:-http://127.0.0.1:8910}"

echo "== [WAIT] UI ready (selfcheck_p0) =="
for i in $(seq 1 60); do
  if curl -fsS -o /dev/null --connect-timeout 1 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] UI ready"
    break
  fi
  sleep 0.2
done

one(){
  local label="$1"
  echo "-- $label --"
  # Print headers we care about, then print time_total separately (avoid awk filtering it out)
  local tt
  tt="$(curl -sS -D- -o /dev/null -w "%{time_total}" "$BASE/vsp5" \
      | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:/ {print}' ; true)"
  # The above prints headers; now print time_total in a separate call
  echo "time_total=$(curl -sS -o /dev/null -w "%{time_total}" "$BASE/vsp5")"
}

# 3 calls: warm disk -> warm ram
echo "-- call #1 (populate cache) --"
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'

echo "-- call #2 (expect HIT-DISK or HIT-RAM) --"
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'

echo "-- call #3 (expect HIT-RAM) --"
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
'''
p.write_text(prefix+smoke+"\n", encoding="utf-8")
print("[OK] patched smoke block (wait + time_total + 3 calls)")
PY
