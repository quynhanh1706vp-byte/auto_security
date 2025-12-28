#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8910"
RID="${1:-}"
WAIT_SEC="${WAIT_SEC:-3600}"   # default 60 phút
SLEEP_SEC="${SLEEP_SEC:-5}"

[ -n "$RID" ] || { echo "Usage: $0 <RID>"; exit 1; }

J="$(curl -sS "$BASE/api/vsp/run_status_v2/$RID")"
CI="$(echo "$J" | jq -r '.ci_run_dir // empty')"
[ -n "$CI" ] || { echo "[ERR] ci_run_dir empty for RID=$RID"; echo "$J" | jq .; exit 2; }

echo "[OK] RID=$RID"
echo "[OK] CI=$CI"

deadline=$((SECONDS+WAIT_SEC))
while [ $SECONDS -lt $deadline ]; do
  # KICS raw outputs (tuỳ runner có thể là kics_results.json hoặc kics.json)
  if [ -f "$CI/kics/kics.json" ] || [ -f "$CI/kics/kics_results.json" ]; then
    echo "[OK] KICS output exists"
    break
  fi
  # show heartbeat
  pct="$(curl -sS "$BASE/api/vsp/run_status_v2/$RID" | jq -r '.progress_pct // 0')"
  echo "[WAIT] progress_pct=$pct (waiting KICS output...)"
  sleep "$SLEEP_SEC"
done

if [ ! -f "$CI/kics/kics.json" ] && [ ! -f "$CI/kics/kics_results.json" ]; then
  echo "[ERR] timeout waiting for KICS output"
  ls -la "$CI/kics" 2>/dev/null || true
  tail -n 80 "$CI/kics/kics.log" 2>/dev/null | sed 's/\r/\n/g' || true
  ps -ef | grep -E "docker run .*checkmarx/kics|/app/bin/kics scan" | grep -v grep || true
  exit 3
fi

# normalize: ensure kics/kics.json exists for gate apply
mkdir -p "$CI/kics"
if [ ! -f "$CI/kics/kics.json" ] && [ -f "$CI/kics/kics_results.json" ]; then
  cp -f "$CI/kics/kics_results.json" "$CI/kics/kics.json"
  echo "[OK] copied kics_results.json -> kics.json"
fi

echo "== RUN gate apply =="
(
  cd "$CI"
  # script này thường dùng relative ./kics nên chạy trong CI là chắc ăn
  python3 /home/test/Data/SECURITY_BUNDLE/bin/vsp_kics_gate_apply_v1.py . \
    || python3 /home/test/Data/SECURITY_BUNDLE/bin/vsp_kics_gate_apply_v1.py "$CI"
)

echo "== kics_summary.json =="
ls -la "$CI/kics/kics_summary.json" 2>/dev/null || true
cat "$CI/kics/kics_summary.json" 2>/dev/null | jq . || true

echo "== status v2 snapshot =="
curl -sS "$BASE/api/vsp/run_status_v2/$RID" | jq '{ok,ci_run_dir,stage_name,progress_pct,kics_verdict,kics_total,kics_counts,degraded_tools}'
