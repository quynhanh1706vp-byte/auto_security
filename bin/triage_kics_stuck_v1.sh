#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8910"
RID="${1:-}"

if [ -z "$RID" ]; then
  echo "[ERR] Usage: $0 <RID>"
  exit 1
fi

echo "RID=$RID"
J="$(curl -sS "$BASE/api/vsp/run_status_v2/$RID")"
echo "$J" | jq '{ok,rid,ci_run_dir,stage_name,stage_index,stage_total,progress_pct,kics_verdict,kics_total}'

CI="$(echo "$J" | jq -r '.ci_run_dir // empty')"
[ -n "$CI" ] || { echo "[ERR] ci_run_dir empty"; exit 2; }

echo "CI=$CI"
echo "== mtime runner.log =="
stat -c '%y %n' "$CI/runner.log" 2>/dev/null || true

echo "== last 80 lines runner.log =="
tail -n 80 "$CI/runner.log" 2>/dev/null | sed 's/\r/\n/g' || true

echo "== kics dir listing =="
ls -la "$CI/kics" 2>/dev/null || true

echo "== mtime kics.log =="
stat -c '%y %n' "$CI/kics/kics.log" 2>/dev/null || true

echo "== last 120 lines kics.log =="
tail -n 120 "$CI/kics/kics.log" 2>/dev/null | sed 's/\r/\n/g' || true

echo "== check outputs =="
for f in "$CI/kics/kics_results.json" "$CI/kics/kics.json" "$CI/kics/kics_summary.json" "$CI/degraded_tools.json"; do
  if [ -f "$f" ]; then
    echo "[OK] exists: $f"
  else
    echo "[MISS] $f"
  fi
done

echo "== docker / kics processes =="
ps -ef | grep -E "kics|docker.*scan" | grep -v grep || true
