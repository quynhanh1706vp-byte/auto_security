#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

ENH="static/js/vsp_dashboard_enhance_v1.js"
BOOT="static/js/vsp_dashboard_charts_bootstrap_v1.js"

[ -f "$ENH" ] || { echo "[ERR] missing $ENH"; exit 1; }
[ -f "$BOOT" ] || { echo "[ERR] missing $BOOT"; exit 1; }

echo "== [1] Extract dashboard-like endpoints from enhance =="
python3 - <<'PY'
import re
from pathlib import Path

t = Path("static/js/vsp_dashboard_enhance_v1.js").read_text(encoding="utf-8", errors="ignore")

urls = set()

# fetch("..."), apiGetJSON("..."), apiGet("...") patterns
for m in re.finditer(r'\bfetch\(\s*["\']([^"\']+)["\']', t):
    urls.add(m.group(1))
for m in re.finditer(r'\bapiGetJSON\(\s*["\']([^"\']+)["\']', t):
    urls.add(m.group(1))
for m in re.finditer(r'\bapiGet\(\s*["\']([^"\']+)["\']', t):
    urls.add(m.group(1))

# keep only likely dashboard endpoints
cand = []
for u in sorted(urls):
    if not u.startswith("/api/"): 
        continue
    if "dash" in u.lower():
        cand.append(u)

print("\n".join(cand))
PY > /tmp/vsp_dash_endpoints.txt

echo "== endpoints found =="
cat /tmp/vsp_dash_endpoints.txt || true

if ! [ -s /tmp/vsp_dash_endpoints.txt ]; then
  echo "[ERR] no dashboard endpoints found in enhance_v1.js"
  echo "[HINT] run: grep -nE \"fetch\\(|apiGetJSON\\(\" $ENH | head -n 80"
  exit 2
fi

echo
echo "== [2] Probe which endpoint actually contains by_severity (recursive jq search) =="
BEST=""
while IFS= read -r u; do
  echo "-- probe $u"
  if curl -sS "http://127.0.0.1:8910$u" \
    | jq -e '..|objects|select(has("by_severity"))|.by_severity' >/dev/null 2>&1; then
      echo "   [HIT] has by_severity"
      BEST="$u"
      break
  else
      echo "   [MISS]"
  fi
done < /tmp/vsp_dash_endpoints.txt

if [ -z "$BEST" ]; then
  echo
  echo "[ERR] none of enhance endpoints returned by_severity via 8910"
  echo "[NEXT] show first 120 lines of enhance fetch logic:"
  grep -nE "fetch\\(|apiGetJSON\\(" "$ENH" | head -n 120
  exit 3
fi

echo
echo "[OK] BEST dashboard endpoint = $BEST"

echo "== [3] Patch bootstrap to prioritize BEST endpoint =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BOOT" "$BOOT.bak_use_best_${TS}"
echo "[BACKUP] $BOOT.bak_use_best_${TS}"

python3 - <<PY
import re
from pathlib import Path

best = "$BEST"

p = Path("$BOOT")
t = p.read_text(encoding="utf-8", errors="ignore")

# replace the CAND_ENDPOINTS array content
m = re.search(r"var\\s+CAND_ENDPOINTS\\s*=\\s*\\[[\\s\\S]*?\\];", t)
if not m:
    raise SystemExit("[ERR] cannot find CAND_ENDPOINTS in bootstrap")

new_arr = f'''var CAND_ENDPOINTS = [
    "{best}",
    "/api/vsp/dashboard_v3_latest",
    "/api/vsp/dashboard_v3_latest.json",
    "/api/vsp/dashboard_v3"
  ];'''

t2 = t[:m.start()] + new_arr + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] updated CAND_ENDPOINTS to start with BEST")
PY

node --check "$BOOT"
echo "[OK] bootstrap parse OK"
