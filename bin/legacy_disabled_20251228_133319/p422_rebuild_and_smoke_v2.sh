#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
from pathlib import Path
s = r"""#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need grep; need sed; need date; need sha256sum; need head; need sort; need uniq

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/smoke/SMOKE_${TS}"
mkdir -p "$OUT"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/smoke.log" >/dev/null; }
fail(){ echo "[FAIL] $*" | tee -a "$OUT/smoke.log" >/dev/null; exit 1; }
ok(){ echo "[OK] $*" | tee -a "$OUT/smoke.log" >/dev/null; }

fetch_head(){ local url="$1" out="$2"; curl -fsS -D "$out" -o /dev/null --connect-timeout 2 --max-time 6 "$url"; }
fetch_body(){ local url="$1" out="$2"; curl -fsS -o "$out" --connect-timeout 2 --max-time 8 --range 0-240000 "$url"; }

log "BASE=$BASE OUT=$OUT"

# wait UI up
up=0
for i in $(seq 1 40); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1; then up=1; break; fi
  sleep 1
done
[ "$up" = "1" ] || fail "UI not reachable: $BASE/vsp5"

pages=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  h="$OUT/HEAD$(echo "$p" | tr '/?' '__').txt"
  b="$OUT/BODY$(echo "$p" | tr '/?' '__').html"
  log "GET $p"
  fetch_head "$BASE$p" "$h" || fail "fetch head $p"
  code="$(awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}' "$h")"
  [ "$code" = "200" ] || fail "$p HTTP=$code"
  fetch_body "$BASE$p" "$b" || fail "fetch body $p"
  sha256sum "$b" >> "$OUT/pages.sha256"

  # commercial layout must be linked
  if ! grep -Fq '/static/css/vsp_layout_commercial_v1.css' "$b"; then
    fail "$p missing commercial CSS link (/static/css/vsp_layout_commercial_v1.css)"
  fi
  # common clean should be loaded (best-effort)
  if ! grep -Fq '/static/js/vsp_c_common_clean_v1.js' "$b"; then
    log "WARN: $p missing vsp_c_common_clean_v1.js (ok if template not patched for that page)"
  fi
done
ok "All pages 200 + saved + CSS link present"

# P412 header must exist on /c/settings and /c/rule_overrides
for p in /c/settings /c/rule_overrides; do
  h="$OUT/HEAD$(echo "$p" | tr '/?' '__').txt"
  awk 'BEGIN{IGNORECASE=1} /^X-VSP-P412-STRIP:/{print}' "$h" | head -n1 | grep -qi 'X-VSP-P412-STRIP: 1' \
    || fail "$p missing X-VSP-P412-STRIP: 1"
done
ok "P412 strip header OK"

# P410 (best-effort): HTML must not contain legacy spam markers
FORBID_RE='installed[[:space:]]+P205|installed[[:space:]]+P306|installed[[:space:]]+P400|json[ _-]?collapse[ _-]?observer'
for i in $(seq 1 10); do
  b="$OUT/p410_vsp5_$i.html"
  fetch_body "$BASE/vsp5" "$b" || fail "p410 fetch /vsp5 #$i"
  if grep -Ein "$FORBID_RE" "$b" >/dev/null 2>&1; then
    grep -Ein "$FORBID_RE" "$b" | head -n 20 | tee -a "$OUT/p410_hits.txt" >/dev/null
    fail "p410: forbidden marker found (see $OUT/p410_hits.txt)"
  fi
done
ok "P410 HTML 10x OK"

# Export discovery from /runs HTML if exists
runs_html="$OUT/BODY__runs.html"
if [ -f "$runs_html" ]; then
  grep -Eoi 'href="[^"]+"' "$runs_html" | sed 's/^href="//;s/"$//' \
    | grep -E '(export|csv|sarif|pdf|zip)' \
    | sed 's#^\(http[s]*://[^/]*\)##' \
    | grep -E '^/' \
    | sort -u > "$OUT/discovered_exports.txt" || true
  if [ -s "$OUT/discovered_exports.txt" ]; then
    ok "Discovered exports: $(wc -l < "$OUT/discovered_exports.txt")"
  else
    log "No export links discovered in /runs (OK)"
  fi
else
  log "WARN: missing $runs_html"
fi

ok "SMOKE PASS. Artifacts in: $OUT"
echo "$OUT" > "$OUT/LATEST_PATH.txt"
"""
Path("bin/p422_smoke_commercial_one_shot_v2.sh").write_text(s, encoding="utf-8")
print("[OK] wrote bin/p422_smoke_commercial_one_shot_v2.sh")
PY

chmod +x bin/p422_smoke_commercial_one_shot_v2.sh
bash bin/p422_smoke_commercial_one_shot_v2.sh
