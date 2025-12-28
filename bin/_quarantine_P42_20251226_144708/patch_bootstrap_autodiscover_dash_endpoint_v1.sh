#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

ENH="static/js/vsp_dashboard_enhance_v1.js"
BOOT="static/js/vsp_dashboard_charts_bootstrap_v1.js"
TMP="/tmp/vsp_dash_endpoints.txt"

[ -f "$ENH" ] || { echo "[ERR] missing $ENH"; exit 1; }
[ -f "$BOOT" ] || { echo "[ERR] missing $BOOT"; exit 1; }

rm -f "$TMP"

echo "== [1] Extract /api/*dash* endpoints from enhance =="
python3 - <<'PY'
import re
from pathlib import Path

t = Path("static/js/vsp_dashboard_enhance_v1.js").read_text(encoding="utf-8", errors="ignore")

urls = set()
for m in re.finditer(r'\bfetch\(\s*["\']([^"\']+)["\']', t):
    urls.add(m.group(1))
for m in re.finditer(r'\bapiGetJSON\(\s*["\']([^"\']+)["\']', t):
    urls.add(m.group(1))
for m in re.finditer(r'\bapiGet\(\s*["\']([^"\']+)["\']', t):
    urls.add(m.group(1))

cand = []
for u in sorted(urls):
    if u.startswith("/api/") and ("dash" in u.lower()):
        cand.append(u)

print("\n".join(cand))
PY | tee "$TMP"

if [ ! -s "$TMP" ]; then
  echo "[ERR] No dashboard endpoints found in enhance."
  echo "[HINT] Show fetch/apiGetJSON lines:"
  grep -nE "fetch\\(|apiGetJSON\\(" "$ENH" | head -n 120
  exit 2
fi

echo
echo "== [2] Probe endpoints for by_severity (recursive jq) =="
BEST=""
while IFS= read -r u; do
  [ -n "$u" ] || continue
  echo "-- probe $u"
  if curl -sS "http://127.0.0.1:8910$u" \
    | jq -e '..|objects|select(has("by_severity"))|.by_severity' >/dev/null 2>&1; then
      echo "   [HIT] by_severity found"
      BEST="$u"
      break
  else
      echo "   [MISS]"
  fi
done < "$TMP"

if [ -z "$BEST" ]; then
  echo
  echo "[ERR] None returned by_severity. That means enhance is NOT fetching a dash endpoint containing by_severity now."
  echo "[NEXT] list ALL /api/ endpoints referenced in enhance (top 80):"
  python3 - <<'PY'
import re
from pathlib import Path
t = Path("static/js/vsp_dashboard_enhance_v1.js").read_text(encoding="utf-8", errors="ignore")
urls=set()
for pat in [r'\bfetch\(\s*["\']([^"\']+)["\']', r'\bapiGetJSON\(\s*["\']([^"\']+)["\']', r'\bapiGet\(\s*["\']([^"\']+)["\']']:
    for m in re.finditer(pat, t):
        u=m.group(1)
        if u.startswith("/api/"): urls.add(u)
for u in sorted(urls)[:80]:
    print(u)
PY
  exit 3
fi

echo
echo "[OK] BEST dashboard endpoint = $BEST"

echo "== [3] Patch bootstrap to prioritize BEST endpoint =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BOOT" "$BOOT.bak_autodash_${TS}"
echo "[BACKUP] $BOOT.bak_autodash_${TS}"

python3 - <<PY
import re
from pathlib import Path
best = "$BEST"
p = Path("$BOOT")
t = p.read_text(encoding="utf-8", errors="ignore")

m = re.search(r"var\\s+CAND_ENDPOINTS\\s*=\\s*\\[[\\s\\S]*?\\];", t)
if not m:
    raise SystemExit("[ERR] cannot find CAND_ENDPOINTS array in bootstrap")

new_arr = f'''var CAND_ENDPOINTS = [
    "{best}",
    "/api/vsp/dashboard_v3_latest",
    "/api/vsp/dashboard_v3_latest.json",
    "/api/vsp/dashboard_v3"
  ];'''

t2 = t[:m.start()] + new_arr + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] updated CAND_ENDPOINTS (BEST first)")
PY

node --check "$BOOT"
echo "[OK] bootstrap patched + parse OK"

echo
echo "== DONE ==  Now Ctrl+Shift+R in browser."
