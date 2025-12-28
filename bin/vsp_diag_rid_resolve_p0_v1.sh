#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE"
RID="${1:-btl86-connector_RUN_20251127_095755_000599}"

echo "== RID RESOLVE DIAG =="
echo "RID=$RID"

tail_run=""
if [[ "$RID" == *"RUN_"* ]]; then
  tail_run="${RID#*RUN_}"
  tail_run="RUN_${tail_run}"
fi

echo "CANDS:"
echo "  1) $RID"
[ -n "$tail_run" ] && echo "  2) $tail_run"

for base in "$ROOT/out" "$ROOT/out_ci"; do
  echo
  echo "== base: $base =="
  for cand in "$RID" "$tail_run"; do
    [ -n "$cand" ] || continue
    d="$base/$cand"
    if [ -d "$d" ]; then
      echo "[FOUND] $d"
      ls -la "$d" | sed -n '1,20p'
      echo "---- reports listing ----"
      ls -la "$d/reports" 2>/dev/null || echo "(no reports/)"
      echo "---- existence ----"
      for f in "reports/index.html" "reports/run_gate_summary.json" "reports/findings_unified.json" "reports/SUMMARY.txt" "SUMMARY.txt"; do
        [ -f "$d/$f" ] && echo "OK  $f" || echo "MISS $f"
      done
    else
      echo "[MISS] $d"
    fi
  done
done
echo
echo "== DONE =="
