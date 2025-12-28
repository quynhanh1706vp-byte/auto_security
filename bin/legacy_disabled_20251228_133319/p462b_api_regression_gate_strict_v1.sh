#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p462b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need curl; need python3; need date

tabs=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)

echo "[INFO] BASE=$BASE OUT=$OUT" | tee -a "$OUT/log.txt"

for p in "${tabs[@]}"; do
  f="$OUT/$(echo "$p" | tr '/?' '__').html"
  curl -fsS --connect-timeout 2 --max-time 6 --range 0-200000 "$BASE$p" -o "$f" \
    || { echo "[RED] fetch fail $p" | tee -a "$OUT/log.txt"; exit 2; }
done

python3 - <<'PY'
from pathlib import Path
import re

out = sorted(Path("out_ci").glob("p462b_*"), key=lambda p:p.name)[-1]
htmls = list(out.glob("*.html"))

api=set()
# capture /api/... until a stopping char
pat = re.compile(r'(/api/[A-Za-z0-9_/\-]+(?:\?[^"\'<>\s\)`\\]*)?)')

for f in htmls:
    s=f.read_text(encoding="utf-8", errors="replace")
    for m in pat.finditer(s):
        u=m.group(1).strip()
        # drop template strings / JS interpolation
        if "${" in u or "encodeURIComponent" in u:
            continue
        # drop braces remnants
        if "{" in u or "}" in u:
            continue
        api.add(u)

api_list = sorted(api, key=lambda x: (0 if x.startswith("/api/ui/") else 1, x))
(out/"api_paths.txt").write_text("\n".join(api_list)+"\n", encoding="utf-8")
print("[OK] extracted", len(api_list), "api paths ->", out/"api_paths.txt")
PY

bad=0
while IFS= read -r ap; do
  [ -n "$ap" ] || continue
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 6 "$BASE$ap" || echo 000)"
  if [ "$code" = "404" ] || [ "${code:0:1}" = "5" ] || [ "$code" = "000" ]; then
    echo "[RED] $code $ap" | tee -a "$OUT/bad.txt"
    bad=$((bad+1))
  else
    echo "[OK]  $code $ap" >> "$OUT/good.txt"
  fi
done < "$OUT/api_paths.txt"

echo "[INFO] bad=$bad" | tee -a "$OUT/log.txt"
[ "$bad" -eq 0 ] || exit 3
echo "[GREEN] P462b PASS" | tee -a "$OUT/log.txt"
