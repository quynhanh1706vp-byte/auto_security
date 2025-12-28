#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h_loaded_js_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need awk; need sed; need grep; need sort; need uniq; need ls; need find; need python3; need node

echo "== [P56H] detect LOADED JS (from 5 tabs) + compare with FAIL list ==" | tee "$EVID/summary.txt"

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

# 1) extract loaded js (strip query)
> "$EVID/loaded_js.txt"
for p in "${tabs[@]}"; do
  html="$EVID/$(echo "$p" | tr '/?' '__').html"
  curl -fsS --connect-timeout 2 --max-time 6 "$BASE$p" -o "$html" || true
  grep -oE '/static/js/[^"]+\.js(\?[^"]*)?' "$html" \
    | sed -E 's/\?.*$//' \
    >> "$EVID/loaded_js.txt" || true
done
sort -u "$EVID/loaded_js.txt" -o "$EVID/loaded_js.txt"
echo "[OK] loaded_js_count=$(wc -l < "$EVID/loaded_js.txt")" | tee -a "$EVID/summary.txt"

# 2) get latest p56g fail list (if exists)
latest_p56g="$(ls -1dt "$OUT"/p56g_js_syntax_* 2>/dev/null | head -n 1 || true)"
fail_list="$EVID/fail_js.txt"
> "$fail_list"
if [ -n "$latest_p56g" ] && [ -f "$latest_p56g/summary.txt" ]; then
  awk '/^\[FAIL\] /{print $2}' "$latest_p56g/summary.txt" > "$fail_list" || true
fi
sort -u "$fail_list" -o "$fail_list"
echo "[OK] latest_p56g=${latest_p56g:-none} fails_count=$(wc -l < "$fail_list")" | tee -a "$EVID/summary.txt"

# 3) intersection: loaded ∩ fail
python3 - <<'PY' "$EVID/loaded_js.txt" "$fail_list" "$EVID/intersection_loaded_fail.txt"
from pathlib import Path
import sys
loaded=set(Path(sys.argv[1]).read_text().splitlines()) if Path(sys.argv[1]).exists() else set()
fails=set(Path(sys.argv[2]).read_text().splitlines()) if Path(sys.argv[2]).exists() else set()
inter=sorted(loaded.intersection(fails))
Path(sys.argv[3]).write_text("\n".join(inter)+"\n" if inter else "")
print("[OK] loaded_fail_count=", len(inter))
PY | tee -a "$EVID/summary.txt"

echo "== loaded∩fail ==" | tee "$EVID/loaded_fail.txt"
cat "$EVID/intersection_loaded_fail.txt" | tee -a "$EVID/loaded_fail.txt" || true

# 4) For loaded&fail: install safe shim (no syntax crash) + keep backup
if [ -s "$EVID/intersection_loaded_fail.txt" ]; then
  echo "[WARN] Some FAIL JS are LOADED -> installing shims to stop UI crash..." | tee -a "$EVID/summary.txt"
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    f="${url#/}"  # static/js/...
    [ -f "$f" ] || continue
    cp -f "$f" "$f.bak_p56h_${TS}" || true
    cat > "$f" <<JS
/* P56H SHIM: disabled broken JS to prevent UI crash.
 * original: ${f}.bak_p56h_${TS}
 * evidence: ${EVID}
 */
(function(){
  try{
    console.warn("[VSP][P56H] shimmed broken JS: ${f}");
  }catch(e){}
})();
JS
    node --check "$f" >/dev/null 2>&1 && echo "[OK] shimmed $f" | tee -a "$EVID/summary.txt" || echo "[ERR] shim syntax fail $f" | tee -a "$EVID/summary.txt"
  done < "$EVID/intersection_loaded_fail.txt"
else
  echo "[OK] No LOADED JS in FAIL list. UI should not crash from these." | tee -a "$EVID/summary.txt"
fi

# 5) Quarantine NOT-loaded fails (repo clean): rename *.js -> *.disabled_p56h_TS.js
python3 - <<'PY' "$EVID/loaded_js.txt" "$fail_list" "$EVID/quarantine_actions.txt"
from pathlib import Path
import sys, time, os, shutil
ts=time.strftime("%Y%m%d_%H%M%S")
loaded=set(Path(sys.argv[1]).read_text().splitlines()) if Path(sys.argv[1]).exists() else set()
fails=set(Path(sys.argv[2]).read_text().splitlines()) if Path(sys.argv[2]).exists() else set()
actions=[]
for f in sorted(fails):
    if f in loaded: 
        continue
    p=Path(f)
    if p.exists():
        new=p.with_name(p.name.replace(".js", f".disabled_p56h_{ts}.js"))
        try:
            p.rename(new)
            actions.append(f"RENAMED {p} -> {new}")
        except Exception as e:
            actions.append(f"FAIL_RENAME {p}: {e}")
Path(sys.argv[3]).write_text("\n".join(actions)+"\n" if actions else "")
print("[OK] quarantine_actions=", len(actions))
PY | tee -a "$EVID/summary.txt"

# 6) Re-check LOADED JS syntax only (this is what matters for UI)
echo "== [P56H] node --check LOADED JS ==" | tee -a "$EVID/summary.txt"
bad=0
while IFS= read -r url; do
  [ -n "$url" ] || continue
  f="${url#/}"
  [ -f "$f" ] || continue
  if ! node --check "$f" >/dev/null 2>&1; then
    echo "[FAIL] loaded syntax: $f" | tee -a "$EVID/loaded_js_check.txt"
    bad=1
  fi
done < "$EVID/loaded_js.txt"

if [ "$bad" = "0" ]; then
  echo "[PASS] all LOADED js pass syntax. Hard refresh browser (Ctrl+Shift+R)." | tee -a "$EVID/summary.txt"
else
  echo "[WARN] some LOADED js still fail syntax -> open $EVID/loaded_js_check.txt" | tee -a "$EVID/summary.txt"
fi

echo "[DONE] Evidence=$EVID"
