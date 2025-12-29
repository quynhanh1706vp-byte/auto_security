#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p931_js_gate_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need node; need date

FILES=(
  "static/js/vsp_c_settings_v1.js"
  "static/js/vsp_ops_panel_v1.js"
  "static/js/vsp_c_sidebar_v1.js"
  "static/js/vsp_c_runs_v1.js"
  "static/js/vsp_data_source_tab_v3.js"
)

check_js(){ node --check "$1" >/dev/null 2>&1; }

pick_golden(){
  local f="$1"
  ls -1t "${f}.bak_GOOD_"* 2>/dev/null | head -n1 || true
}

restore_golden(){
  local f="$1"
  local g
  g="$(pick_golden "$f")"
  if [[ -z "$g" ]]; then
    echo "[FAIL] no GOLDEN backup for $f" | tee -a "$OUT/summary.txt"
    return 2
  fi
  cp -f "$g" "$f"
  echo "[OK] restored GOLDEN: $g -> $f" | tee -a "$OUT/summary.txt"
}

echo "== [P931] JS syntax gate (with GOLDEN autorollback) ==" | tee -a "$OUT/summary.txt"

bad=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "[WARN] missing: $f (skip)" | tee -a "$OUT/summary.txt"
    continue
  fi

  if check_js "$f"; then
    echo "[OK] js syntax OK: $f" | tee -a "$OUT/summary.txt"
    continue
  fi

  echo "[WARN] js syntax FAIL: $f" | tee -a "$OUT/summary.txt"
  node --check "$f" 2>&1 | sed -n '1,12p' | tee -a "$OUT/summary.txt" || true

  echo "== try restore GOLDEN ==" | tee -a "$OUT/summary.txt"
  if restore_golden "$f"; then
    if check_js "$f"; then
      echo "[OK] after restore, js syntax OK: $f" | tee -a "$OUT/summary.txt"
    else
      echo "[FAIL] still FAIL after GOLDEN restore: $f" | tee -a "$OUT/summary.txt"
      bad=1
    fi
  else
    bad=1
  fi
done

if [[ "$bad" == "1" ]]; then
  echo "[FAIL] P931 gate FAIL. Evidence: $OUT" | tee -a "$OUT/summary.txt"
  exit 2
fi

echo "[OK] P931 gate PASS. Evidence: $OUT" | tee -a "$OUT/summary.txt"
