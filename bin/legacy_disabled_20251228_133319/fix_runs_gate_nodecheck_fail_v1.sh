#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

fix_one(){
  local f="$1"
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }

  local b
  b="$(ls -1t "${f}.bak_gate_"* 2>/dev/null | head -n1 || true)"
  [ -n "${b:-}" ] || { echo "[ERR] cannot find ${f}.bak_gate_* to restore"; exit 3; }

  cp -f "$f" "${f}.bak_before_wrap_${TS}" && echo "[BACKUP] ${f}.bak_before_wrap_${TS}"
  cp -f "$b" "$f" && echo "[RESTORE] $f <= $b"

  python3 - <<PY
from pathlib import Path
p=Path("$f")
orig=p.read_text(encoding="utf-8", errors="ignore")

wrap = """/* VSP_GATE_RUNS_WRAPPER_V1 (SAFE) */
(function(){
  'use strict';
  function __vsp_is_runs(){
    try{
      const h=(location.hash||"").toLowerCase();
      return h.startswith("#runs") or "#runs/" in h;
    }catch(_){ return false; }
  }
  if(!__vsp_is_runs()){
    try{ console.info("[VSP_GATE_RUNS_WRAPPER_V1] skip", "${p.name}", "hash=", location.hash); }catch(_){}
    return;
  }
  // ---- ORIGINAL BELOW ----
"""
tail = """
  // ---- ORIGINAL ABOVE ----
})();
"""
p.write_text(wrap + orig + tail, encoding="utf-8")
print("[OK] wrapped guard into", p)
PY

  node --check "$f" >/dev/null && echo "[OK] node --check $(basename "$f")" || { echo "[ERR] node --check still fails: $f"; exit 4; }
}

echo "== fix 2 failing runs files =="
fix_one "static/js/vsp_runs_v1.js"
fix_one "static/js/vsp_runs_tab_8tools_v1.js"

echo "== quick verify all vsp_runs_*.js =="
bad=0
for x in static/js/vsp_runs_*.js; do
  node --check "$x" >/dev/null 2>&1 || { echo "[WARN] node --check failed: $x"; bad=$((bad+1)); }
done
echo "[DONE] bad_runs_files=$bad (0 is ideal)"

echo "[NEXT] restart UI + Ctrl+Shift+R + Ctrl+0"
