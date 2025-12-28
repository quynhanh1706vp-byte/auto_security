#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_ridbootstrap_${TS}"
echo "[BACKUP] ${JS}.bak_ridbootstrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RID_BOOTSTRAP_FALLBACK_V1"
if marker in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

helper = r"""
/* VSP_P0_RID_BOOTSTRAP_FALLBACK_V1
   - Prefer rid_latest_gate_root endpoints
   - Persist last good rid in localStorage
   - If still no rid => allow ridless mode (backend run_file_allow can serve latest)
*/
async function __vsp_p0_getRidLatest(){
  const cacheKey = "vsp_last_good_rid_v1";
  const saved = (()=>{ try{return localStorage.getItem(cacheKey)||""}catch(e){return ""} })();

  const urls = [
    "/api/vsp/rid_latest_gate_root",
    "/api/vsp/rid_latest_gate_root_v1",
    "/api/vsp/rid_latest",
  ];

  for (const u of urls){
    try{
      const r = await fetch(u, {cache:"no-store"});
      if (!r.ok) continue;
      const j = await r.json().catch(()=>null);
      const rid = (j && (j.rid || j.run_id || j.latest_rid)) ? (j.rid || j.run_id || j.latest_rid) : "";
      if (rid){
        try{ localStorage.setItem(cacheKey, rid); }catch(e){}
        return rid;
      }
    }catch(e){}
  }
  // fallback to saved rid if present
  if (saved) return saved;
  return "";
}
"""

# Inject helper after first IIFE start if possible, else at top.
if "(()=>{" in s:
    s = s.replace("(()=>{", "(()=>{\n" + helper + "\n", 1)
elif "(() =>" in s:
    s = s.replace("(() =>", "(() =>\n" + helper + "\n", 1)
else:
    s = helper + "\n" + s

# Patch: replace any hard-coded /api/vsp/rid_latest fetch with gate_root endpoint (best chance)
s = s.replace("/api/vsp/rid_latest", "/api/vsp/rid_latest_gate_root")

# Patch: soften “give up if rid not ready” guards
# Common patterns:
#   if(!rid){ ... return; }
#   if (!rid_ready) { ... return; }
# We keep running with rid="" (ridless).
s = re.sub(
    r'if\s*\(\s*!\s*rid\s*\)\s*\{\s*[^}]{0,280}?return\s*;\s*\}',
    'if(!rid){ console.warn("[VSP][P0] rid missing => ridless mode"); rid=""; }\n',
    s,
    count=2,
    flags=re.S
)

# Patch: if there is a "gave up (rid still not ready)" log, do not return.
s = re.sub(
    r'gave up\s*\(\s*rid\s*still\s*not\s*ready\s*\)[^;\n]*;?\s*return\s*;?',
    'console.warn("[VSP][P0] rid not ready => continue ridless");',
    s,
    count=2,
    flags=re.I
)

# Patch: ensure code actually uses the helper at least once by rewriting common rid init call.
# Replace first occurrence of "fetchRidLatest" / "rid_latest" style init if present.
s = re.sub(
    r'(const|let|var)\s+rid\s*=\s*[^;]*rid_latest[^;]*;',
    r'\1 rid = await __vsp_p0_getRidLatest();',
    s,
    count=1,
    flags=re.I
)

p.write_text(s, encoding="utf-8")
print("[OK] patched GateStory: rid bootstrap fallback + ridless mode")
PY

echo "== smoke: GateStory now references rid_latest_gate_root =="
grep -n "rid_latest_gate_root" "$JS" | head -n 5 || true

echo "== quick API check =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root" | head -c 220; echo
curl -sS "$BASE/api/vsp/rid_latest" | head -c 220; echo

echo "[DONE] Ctrl+Shift+R /vsp5"
