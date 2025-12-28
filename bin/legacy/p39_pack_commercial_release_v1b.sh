#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT_ROOT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$OUT_ROOT/RELEASE_UI_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need wc; need sha256sum; need date; need head; need grep

echo "== [0] warm selfcheck =="
ok=0
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 2 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] selfcheck ok (try#$i)"
    ok=1
    break
  fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] selfcheck fail"; exit 2; }

echo "== [1] pick RID =="
curl -sS --connect-timeout 2 --max-time 10 \
  "$BASE/api/vsp/runs?limit=1&offset=0" -o "$OUT/runs.json" || true

RID="$(python3 - <<'PY' 2>/dev/null || true
import json
try:
  j=json.load(open("'"$OUT/runs.json"'","r",encoding="utf-8", errors="replace"))
  runs=j.get("runs") or []
  r0=runs[0] if runs and isinstance(runs[0], dict) else {}
  print((r0.get("rid") or r0.get("id") or "").strip())
except Exception:
  print("")
PY
)"
RID="${RID:-VSP_CI_20251211_133204}"
echo "RID=$RID" | tee "$OUT/RID.txt"

echo "== [2] export html/pdf/zip =="
: > "$OUT/EXPORT_SUMMARY.txt"
for fmt in html pdf zip; do
  url="$BASE/api/vsp/export?rid=$RID&fmt=$fmt"
  hdr="$OUT/export_${fmt}.hdr"
  bin="$OUT/export_${fmt}.${fmt}"
  curl -g -sS --connect-timeout 2 --max-time 25 -D "$hdr" -o "$bin" "$url" || true

  ct="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{print $0; exit}' "$hdr" | tr -d '\r' || true)"
  sz="$(wc -c <"$bin" 2>/dev/null || echo 0)"

  echo "--- $fmt ---" >> "$OUT/EXPORT_SUMMARY.txt"
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:|^Content-Length:/{print}' "$hdr" >> "$OUT/EXPORT_SUMMARY.txt"
  echo "bytes=$sz" >> "$OUT/EXPORT_SUMMARY.txt"
  echo >> "$OUT/EXPORT_SUMMARY.txt"

  # contract hard check
  case "$fmt" in
    html) echo "$ct" | grep -qi 'text/html' || { echo "[ERR] export html CT wrong: $ct"; exit 2; } ;;
    pdf)  echo "$ct" | grep -qi 'application/pdf' || { echo "[ERR] export pdf CT wrong: $ct"; exit 2; } ;;
    zip)  echo "$ct" | grep -qi 'application/zip' || { echo "[ERR] export zip CT wrong: $ct"; exit 2; } ;;
  esac
  [ "$sz" -gt 0 ] || { echo "[ERR] export $fmt empty"; exit 2; }
done
echo "[OK] export contract PASS"

echo "== [3] audit v3b (must PASS) =="
set +e
VSP_UI_BASE="$BASE" bash bin/commercial_ui_audit_v3b.sh > "$OUT/audit_v3b.txt" 2> "$OUT/audit_v3b.err"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[ERR] audit_v3b FAIL (rc=$rc)"
  echo "---- RED/AMBER lines ----"
  grep -nE '^\[(RED|AMBER)\]' "$OUT/audit_v3b.txt" || true
  echo "---- tail ----"
  tail -n 60 "$OUT/audit_v3b.txt" || true
  exit 2
fi
echo "[OK] audit_v3b PASS"

echo "== [4] hashes =="
( cd "$OUT" && sha256sum * > SHA256SUMS.txt )

echo "== [DONE] =="
echo "OUT=$OUT"
echo "Files:"
ls -lh "$OUT"
echo
echo "Audit tail:"
tail -n 15 "$OUT/audit_v3b.txt"
