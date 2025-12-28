#!/usr/bin/env bash
set -euo pipefail

CI="${1:-}"
if [ -z "$CI" ]; then
  CI="$(ls -1dt /home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_* | head -n 1)"
fi
echo "[PROOF] CI=$CI"

KLOG="$CI/kics/kics.log"
DGD="$CI/degraded_tools.json"

echo "[PROOF] ps (kics for this CI)..."
ps -ef | grep -F "$CI/kics" | grep -E "kics scan|timeout" | grep -v grep || true

# wait loop: up to 120s
DEADLINE=$((SECONDS + 120))
while [ $SECONDS -lt $DEADLINE ]; do
  # if degraded marker appears -> break
  if [ -f "$KLOG" ] && grep -q "\[KICS_V3\]\[DEGRADED\]" "$KLOG" 2>/dev/null; then
    echo "[PROOF] degraded marker found in kics.log"
    break
  fi

  # if no kics process for this CI -> break
  if ! ps -ef | grep -F "$CI/kics" | grep -E "kics scan|timeout" | grep -v grep >/dev/null 2>&1; then
    echo "[PROOF] kics process for this CI is gone"
    break
  fi

  sleep 2
done

echo "[PROOF] Result:"
if [ -f "$DGD" ]; then
  echo "[OK] degraded_tools.json exists: $DGD"
  (cat "$DGD" | jq . 2>/dev/null) || cat "$DGD"
  exit 0
fi

echo "[WARN] degraded_tools.json not found yet at: $DGD"
echo "== last 80 runner.log =="
tail -n 80 "$CI/runner.log" | sed 's/\r/\n/g' || true
echo "== last 120 kics.log =="
tail -n 120 "$KLOG" 2>/dev/null | sed 's/\r/\n/g' || echo "no kics.log"
echo "== ps (kics for this CI) =="
ps -ef | grep -F "$CI/kics" | grep -E "kics scan|timeout" | grep -v grep || true

exit 1
