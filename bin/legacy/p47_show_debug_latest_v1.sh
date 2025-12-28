#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

D="$(ls -1dt out_ci/p47_debug_* 2>/dev/null | head -n 1 || true)"
[ -n "$D" ] || { echo "[ERR] no out_ci/p47_debug_* folder"; exit 2; }

echo "== [P47] latest debug folder =="
echo "$D"
echo

echo "== systemctl snapshot =="
sed -n '1,220p' "$D/systemctl.txt" 2>/dev/null || echo "(missing systemctl.txt)"
echo

echo "== journal tail (last 120 lines) =="
tail -n 120 "$D/journal_tail.txt" 2>/dev/null || echo "(missing journal_tail.txt)"
echo

echo "== ports (ss) =="
cat "$D/ports_ss.txt" 2>/dev/null || echo "(missing ports_ss.txt)"
echo

echo "== unit file (first 120 lines) =="
sed -n '1,120p' "$D/unit.txt" 2>/dev/null || echo "(missing unit.txt)"
echo

echo "== override (first 80 lines) =="
sed -n '1,80p' "$D/override.txt" 2>/dev/null || echo "(missing override.txt)"
