#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p462_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need curl; need python3; need date

tabs=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)

echo "[INFO] BASE=$BASE OUT=$OUT" | tee -a "$OUT/log.txt"

# 1) fetch HTML of tabs
for p in "${tabs[@]}"; do
  f="$OUT/$(echo "$p" | tr '/?' '__').html"
  curl -fsS --connect-timeout 2 --max-time 6 --range 0-200000 "$BASE$p" -o "$f" \
    || { echo "[RED] fetch fail $p" | tee -a "$OUT/log.txt"; exit 2; }
done

# 2) extract api paths from HTML (best-effort)
python3 - <<'PY'
from pathlib import Path
import re, json

out = Path("out_ci").glob("p462_*")
out = sorted(out, key=lambda p: p.name)[-1]
htmls = list(out.glob("*.html"))

api = set()
pat = re.compile(r'(/api/[a-zA-Z0-9_/\-]+)(\?[^\s"\'<>\\]*)?')
for f in htmls:
    s = f.read_text(encoding="utf-8", errors="replace")
    for m in pat.finditer(s):
        api.add((m.group(1) + (m.group(2) or "")).strip())

# keep stable order: /api/ui first, then others
api_list = sorted(api, key=lambda x: (0 if x.startswith("/api/ui/") else 1, x))
(out / "api_paths.txt").write_text("\n".join(api_list) + "\n", encoding="utf-8")
print("[OK] extracted", len(api_list), "api paths ->", out / "api_paths.txt")
PY

# 3) probe each api: fail on 404/5xx, allow 2xx/3xx/401/403/400 (param missing is fine)
bad=0
while IFS= read -r ap; do
  [ -n "$ap" ] || continue
  url="$BASE$ap"
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 6 "$url" || echo 000)"
  if [ "$code" = "404" ] || [ "${code:0:1}" = "5" ] || [ "$code" = "000" ]; then
    echo "[RED] $code $ap" | tee -a "$OUT/bad.txt"
    bad=$((bad+1))
  else
    echo "[OK]  $code $ap" >> "$OUT/good.txt"
  fi
done < "$OUT/api_paths.txt"

echo "[INFO] bad=$bad (see $OUT/bad.txt if any)" | tee -a "$OUT/log.txt"
[ "$bad" -eq 0 ] || exit 3
echo "[GREEN] P462 PASS (no 404/5xx on extracted APIs)" | tee -a "$OUT/log.txt"
