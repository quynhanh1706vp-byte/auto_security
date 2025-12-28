#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

CANDS=()
for f in static/js/vsp_dashboard_gate_story_v1.js static/js/vsp_bundle_commercial_v1.js static/js/vsp_bundle_commercial_v2.js; do
  [ -f "$f" ] && CANDS+=("$f")
done
[ "${#CANDS[@]}" -gt 0 ] || { echo "[ERR] no target JS found"; exit 2; }

for f in "${CANDS[@]}"; do
  cp -f "$f" "${f}.bak_ridresp_all_${TS}"
  echo "[BACKUP] ${f}.bak_ridresp_all_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

marker="VSP_P1_GATE_STORY_RID_FROM_RESPONSE_ALL_V1"
targets=[p for p in [
  Path("static/js/vsp_dashboard_gate_story_v1.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
] if p.exists()]

ins = r"""
/* VSP_P1_GATE_STORY_RID_FROM_RESPONSE_ALL_V1 */
try{
  if (gate && gate.run_id && typeof gate.run_id === "string" && gate.run_id.trim()){
    var __rid_eff = gate.run_id.trim();
    // overwrite rid used by logs/UI
    try{ rid = __rid_eff; }catch(e){}
    try{ window.vsp_rid_latest = __rid_eff; }catch(e){}
    try{ localStorage.setItem('vsp_rid_latest_v1', __rid_eff); }catch(e){}
    try{
      var el = document.getElementById('vsp_live_rid');
      if (el) el.textContent = 'rid_latest: ' + __rid_eff;
    }catch(e){}
    try{ console.log("[GateStory] effective rid from response:", __rid_eff); }catch(e){}
  }
}catch(e){}
"""

patched=0
for p in targets:
    s=p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        continue

    # best place: right after a JSON.parse(..) assigned into gate variable
    m = re.search(r'\b(gate\s*=\s*JSON\.parse\([^;]*\)\s*;)', s)
    if m:
        idx=m.end()
        s2=s[:idx]+"\n"+ins+"\n"+s[idx:]
    else:
        # fallback: inject after first mention of "GateStoryV1" marker
        m2=re.search(r'GateStoryV1', s)
        if m2:
            idx=m2.start()
            s2=s[:idx]+ins+"\n"+s[idx:]
        else:
            # last resort: prepend (still safe)
            s2=ins+"\n"+s

    p.write_text(s2, encoding="utf-8")
    patched += 1
    print("[OK] patched", p)

print("[DONE] patched_files=", patched)
PY

echo "== next =="
echo "1) Browser console:"
echo "   localStorage.removeItem('vsp_rid_latest_v1'); localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "2) Ctrl+F5 /vsp5"
