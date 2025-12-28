#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT_ROOT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$OUT_ROOT/RELEASE_UI_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need wc; need sha256sum; need date; need head

echo "== [0] warm =="
ok=0
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 2 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] selfcheck fail"; exit 2; }

echo "== [1] pick RID =="
curl -sS --connect-timeout 2 --max-time 10 "$BASE/api/vsp/runs?limit=1&offset=0" -o "$OUT/runs.json" || true
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
for fmt in html pdf zip; do
  url="$BASE/api/vsp/export?rid=$RID&fmt=$fmt"
  hdr="$OUT/export_${fmt}.hdr"
  bin="$OUT/export_${fmt}.${fmt}"
  curl -g -sS --connect-timeout 2 --max-time 25 -D "$hdr" -o "$bin" "$url" || true
  echo "--- $fmt ---" >> "$OUT/EXPORT_SUMMARY.txt"
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:|^Content-Length:/{print}' "$hdr" >> "$OUT/EXPORT_SUMMARY.txt"
  echo "bytes=$(wc -c <"$bin" 2>/dev/null || echo 0)" >> "$OUT/EXPORT_SUMMARY.txt"
  echo >> "$OUT/EXPORT_SUMMARY.txt"
done

echo "== [3] include audit verdict =="
VSP_UI_BASE="$BASE" bash bin/commercial_ui_audit_v3b.sh > "$OUT/audit_v3b.txt" || true
tail -n 40 "$OUT/audit_v3b.txt" > "$OUT/audit_v3b_tail.txt"

echo "== [4] hashes =="
(
  cd "$OUT"
  sha256sum * 2>/dev/null || true
) > "$OUT/SHA256SUMS.txt"

echo "== [DONE] =="
echo "OUT=$OUT"
echo "Key files:"
ls -lh "$OUT" | awk '{print $5,$6,$7,$8,$9}' | sed 's/^/  /'
echo
echo "Audit tail:"
tail -n 10 "$OUT/audit_v3b.txt" || true
