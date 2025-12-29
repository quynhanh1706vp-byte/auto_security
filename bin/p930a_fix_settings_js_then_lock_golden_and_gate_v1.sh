#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p930a_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need node; need python3; need date; need curl

F="static/js/vsp_c_settings_v1.js"
OPS="static/js/vsp_ops_panel_v1.js"

js_ok(){ node --check "$1" >/dev/null 2>&1; }

echo "== [P930A] check current settings js =="
if [ ! -f "$F" ]; then
  echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 3
fi

if js_ok "$F"; then
  echo "[OK] current JS syntax OK: $F" | tee -a "$OUT/summary.txt"
else
  echo "[WARN] current JS syntax FAIL: $F" | tee -a "$OUT/summary.txt"
  node --check "$F" || true

  echo "== [P930A] try restore from newest GOOD backup that passes node --check =="
  picked=""
  for b in $(ls -1t "${F}".bak_GOOD_* "${F}".bak_p923b_* "${F}".bak_p92*_* "${F}".bak_* 2>/dev/null || true); do
    [ -f "$b" ] || continue
    if js_ok "$b"; then
      cp -f "$b" "$F"
      picked="$b"
      echo "[OK] restored from $picked" | tee -a "$OUT/summary.txt"
      break
    fi
  done

  if [ -z "$picked" ]; then
    echo "== [P930A] no good backup found => rebuild via P923B (commercial full) =="
    if [ -x bin/p923b_rebuild_settings_js_full_commercial_v1.sh ]; then
      bash bin/p923b_rebuild_settings_js_full_commercial_v1.sh | tee -a "$OUT/p923b.txt"
    else
      echo "[ERR] missing bin/p923b_rebuild_settings_js_full_commercial_v1.sh" | tee -a "$OUT/log.txt"
      exit 4
    fi
  fi

  echo "== [P930A] re-check settings js MUST be OK =="
  if ! js_ok "$F"; then
    echo "[FAIL] still syntax FAIL after restore/rebuild: $F" | tee -a "$OUT/log.txt"
    node --check "$F" || true
    exit 5
  fi
  echo "[OK] fixed settings JS syntax" | tee -a "$OUT/summary.txt"
fi

echo "== [P930A] lock GOLDEN backups =="
cp -f "$F" "${F}.bak_GOOD_${TS}"
echo "[OK] ${F}.bak_GOOD_${TS}" | tee -a "$OUT/golden.txt"
if [ -f "$OPS" ] && js_ok "$OPS"; then
  cp -f "$OPS" "${OPS}.bak_GOOD_${TS}"
  echo "[OK] ${OPS}.bak_GOOD_${TS}" | tee -a "$OUT/golden.txt"
fi

echo "== [P930A] run gates (must PASS) =="
bash bin/p921b_js_syntax_gate_autofix_autorollback_v2.sh | tee "$OUT/p921b.txt"
bash bin/p918_p0_smoke_no_error_v1.sh | tee "$OUT/p918.txt"
bash bin/p920_p0plus_ops_evidence_logs_v1.sh | tee "$OUT/p920.txt"
bash bin/p922b_pack_release_snapshot_no_warning_v2.sh | tee "$OUT/p922b.txt"

echo "== [P930A] DONE =="
echo "[OK] Evidence: $OUT"
