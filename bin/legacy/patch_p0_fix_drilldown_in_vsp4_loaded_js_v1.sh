#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

JS_LIST="$(curl -sS http://127.0.0.1:8910/vsp4 | grep -oE "/static/js/[^\"']+\.js[^\"']*" | sed 's/^\/static/static/' | sed 's/\?.*$//' | sort -u)"
echo "== JS from /vsp4 =="
echo "$JS_LIST"

patched=0
for F in $JS_LIST; do
  [ -f "$F" ] || { echo "[SKIP] missing $F"; continue; }
  if ! grep -q "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" "$F"; then
    echo "[NOHIT] $F"
    continue
  fi
  echo "== PATCH: $F =="
  cp -f "$F" "$F.bak_p0_vsp4_${TS}"
  echo "[BACKUP] $F.bak_p0_vsp4_${TS}"

  TARGET_FILE="$F" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["TARGET_FILE"])
s = p.read_text(encoding="utf-8", errors="ignore")

pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
repl = r'(typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function"?VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:function(){try{console.info("[VSP][P0] drilldown missing -> stub");}catch(_){ } return {open(){},show(){},close(){},destroy(){}};})('
s2, n = re.subn(pat, repl, s)

if "/* P0_DRILLDOWN_STUB_VSP4 */" not in s2:
  header = r'''/* P0_DRILLDOWN_STUB_VSP4 */
(function(){
  try{
    if (typeof window === "undefined") return;
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.info("[VSP][P0] drilldown stub called"); }catch(_){}
        return {open(){},show(){},close(){},destroy(){}};
      };
    }
  }catch(_){}
})();
'''
  s2 = header + "\n" + s2

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p, "callsites=", n)
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
  patched=$((patched+1))
done

echo "[DONE] patched_files=$patched"
