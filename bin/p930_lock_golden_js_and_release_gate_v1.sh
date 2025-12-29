#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p930_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need node; need python3; need date; need curl

FILES=(
  "static/js/vsp_c_settings_v1.js"
  "static/js/vsp_ops_panel_v1.js"
  "static/js/vsp_c_sidebar_v1.js"
  "static/js/vsp_c_runs_v1.js"
  "static/js/vsp_dashboard_*.js"
)

echo "== [P930] JS syntax check =="
for pat in "${FILES[@]}"; do
  for f in $pat; do
    [ -f "$f" ] || continue
    if node --check "$f" >/dev/null 2>&1; then
      echo "[OK] js syntax OK: $f" | tee -a "$OUT/js_ok.txt"
    else
      echo "[FAIL] js syntax FAIL: $f" | tee -a "$OUT/js_fail.txt"
      node --check "$f" || true
      exit 3
    fi
  done
done

echo "== [P930] lock GOLDEN backups (for rollback) =="
for f in static/js/vsp_c_settings_v1.js static/js/vsp_ops_panel_v1.js; do
  [ -f "$f" ] || continue
  cp -f "$f" "${f}.bak_GOOD_${TS}"
  echo "[OK] ${f}.bak_GOOD_${TS}" | tee -a "$OUT/golden.txt"
done

echo "== [P930] run gates =="
bash bin/p921b_js_syntax_gate_autofix_autorollback_v2.sh | tee "$OUT/p921b.txt"
bash bin/p918_p0_smoke_no_error_v1.sh | tee "$OUT/p918.txt"
bash bin/p920_p0plus_ops_evidence_logs_v1.sh | tee "$OUT/p920.txt"
bash bin/p922b_pack_release_snapshot_no_warning_v2.sh | tee "$OUT/p922b.txt"

echo "== [P930] DONE =="
echo "[OK] Evidence: $OUT"
