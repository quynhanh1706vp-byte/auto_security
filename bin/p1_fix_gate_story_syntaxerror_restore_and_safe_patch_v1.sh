#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need sort; need head; need grep

TS="$(date +%Y%m%d_%H%M%S)"

FILES=()
[ -f static/js/vsp_dashboard_gate_story_v1.js ] && FILES+=(static/js/vsp_dashboard_gate_story_v1.js)
[ -f static/js/vsp_bundle_commercial_v1.js ] && FILES+=(static/js/vsp_bundle_commercial_v1.js)
[ -f static/js/vsp_bundle_commercial_v2.js ] && FILES+=(static/js/vsp_bundle_commercial_v2.js)

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no target JS under static/js"; exit 2; }

echo "== RESTORE from latest .bak_ridresp_all_* (if any) =="
for f in "${FILES[@]}"; do
  bak="$(ls -1 "${f}.bak_ridresp_all_"* 2>/dev/null | sort | tail -n 1 || true)"
  if [ -n "${bak:-}" ] && [ -f "$bak" ]; then
    cp -f "$bak" "$f"
    echo "[RESTORED] $f <= $bak"
  else
    echo "[SKIP] no ridresp backup for $f"
  fi
done

echo "== SAFE PATCH: insert only after gate = JSON.parse(...) statement =="
python3 - <<'PY'
from pathlib import Path

targets = [
  Path("static/js/vsp_dashboard_gate_story_v1.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
]
marker = "VSP_P1_GATE_STORY_RID_FROM_RESPONSE_SAFE_V1"

SNIP = r"""
/* VSP_P1_GATE_STORY_RID_FROM_RESPONSE_SAFE_V1 */
try{
  var __rid_eff = (typeof gate==="object" && gate && gate.run_id!=null) ? String(gate.run_id).trim() : "";
  if (__rid_eff){
    try{ rid = __rid_eff; }catch(e){}
    try{ window.vsp_rid_latest = __rid_eff; }catch(e){}
    try{ localStorage.setItem("vsp_rid_latest_v1", __rid_eff); }catch(e){}
    try{
      var el=document.getElementById("vsp_live_rid");
      if(el) el.textContent = "rid_latest: " + __rid_eff;
    }catch(e){}
    try{ console.log("[GateStory] effective rid from response:", __rid_eff); }catch(e){}
  }
}catch(e){}
"""

def safe_insert_after_json_parse(s: str) -> str | None:
    if marker in s:
        return None
    # find a gate JSON.parse assignment
    needles = ["gate=JSON.parse(", "gate = JSON.parse("]
    pos = -1
    for nd in needles:
        pos = s.find(nd)
        if pos >= 0:
            break
    if pos < 0:
        return None
    end = s.find(");", pos)
    if end < 0:
        return None
    end += 2
    return s[:end] + "\n" + SNIP + "\n" + s[end:]

patched = 0
skipped = 0
for p in targets:
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    s2 = safe_insert_after_json_parse(s)
    if s2 is None:
        skipped += 1
        continue
    p.write_text(s2, encoding="utf-8")
    patched += 1
    print("[OK] patched safe:", p)

print("[DONE] patched=", patched, "skipped=", skipped)
PY

echo
echo "== OPTIONAL: quick syntax check if node exists =="
if command -v node >/dev/null 2>&1; then
  for f in "${FILES[@]}"; do
    node --check "$f" && echo "[OK] node --check $f"
  done
else
  echo "[INFO] node not found; skip node --check"
fi

echo
echo "== NEXT (browser) =="
echo "1) Open /vsp5"
echo "2) Console run:"
echo "   localStorage.removeItem('vsp_rid_latest_v1'); localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "3) Ctrl+F5"
