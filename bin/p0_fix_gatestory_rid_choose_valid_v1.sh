#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_ridfix_${TS}"
echo "[BACKUP] ${JS}.bak_ridfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RID_CHOOSE_VALID_V1"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

inject = r'''
/* ===================== VSP_P0_RID_CHOOSE_VALID_V1 =====================
   Goal: NEVER scrape stale RID. Allow ?rid=... pin + validate via run_file_allow.
   If pinned/last rid invalid -> fallback to /api/vsp/runs list and pick first valid.
===================== */
(function(){
  try{
    if (window.__VSP_RID_CHOOSE_VALID_V1) return;
    window.__VSP_RID_CHOOSE_VALID_V1 = true;

    const RID_RE = /\b(?:VSP_CI_RUN|RUN)_[0-9]{8}_[0-9]{6}\b/;

    function getPinnedRid(){
      try{
        const u = new URL(window.location.href);
        const rid = (u.searchParams.get("rid")||"").trim();
        if (rid && RID_RE.test(rid)) return rid.match(RID_RE)[0];
      }catch(e){}
      return null;
    }

    function getStoredRid(){
      try{
        const rid = (localStorage.getItem("vsp_rid_pin")||"").trim();
        if (rid && RID_RE.test(rid)) return rid.match(RID_RE)[0];
      }catch(e){}
      return null;
    }

    function storeRid(rid){
      try{ localStorage.setItem("vsp_rid_pin", rid); }catch(e){}
    }

    async function getJSON(url){
      const r = await fetch(url, {credentials:"same-origin"});
      const t = await r.text();
      let j=null;
      try{ j=JSON.parse(t); }catch(e){ j={ok:false, err:"bad_json", _text:t.slice(0,240)}; }
      if (j && typeof j==="object"){ j.__http_status=r.status; j.__http_ok=r.ok; }
      return j;
    }

    async function isRidValid(rid){
      // validate by a small allowlisted file
      const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`;
      const j = await getJSON(url);
      // accept both shapes: {ok:true,data:{...}} OR {meta/findings...} for other endpoints
      if (j && j.ok === True) return true; // (never hit in JS, kept for readability)
      if (j && j.ok === true) return true;
      // some endpoints return {meta:..,findings:..} without ok
      if (j && typeof j==="object" && (j.meta || j.findings)) return true;
      return false;
    }

    async function pickRidFromRuns(){
      const runs = await getJSON("/api/vsp/runs?limit=50");
      const arr = (runs && runs.runs && Array.isArray(runs.runs)) ? runs.runs : (Array.isArray(runs)?runs:[]);
      for (const r of arr){
        const rid = String(r.rid || r.id || r.run_id || "").trim();
        if (!rid || !RID_RE.test(rid)) continue;
        try{
          if (await isRidValid(rid)) return rid;
        }catch(e){}
      }
      return null;
    }

    window.__vsp_choose_rid_valid = async function(){
      // priority: ?rid= -> stored -> existing window.__VSP_GATE_RID -> fallback runs
      let rid = getPinnedRid() || getStoredRid() || (window.__VSP_GATE_RID && String(window.__VSP_GATE_RID)) || null;
      if (rid && RID_RE.test(rid)) rid = rid.match(RID_RE)[0];

      if (rid){
        try{
          const ok = await isRidValid(rid);
          if (ok){
            storeRid(rid);
            return rid;
          }
        }catch(e){}
      }

      const rid2 = await pickRidFromRuns();
      if (rid2){
        storeRid(rid2);
        return rid2;
      }
      return rid || null;
    };

    console.log("[VSP][RIDFIX] installed choose-valid rid hook");
  }catch(e){
    console.warn("[VSP][RIDFIX] install failed:", e);
  }
})();
'''


# Insert inject near top: after first IIFE header (best-effort)
# If file begins with (()=>{ ... we'll put after first line.
lines = s.splitlines(True)
if len(lines) > 1:
    lines.insert(1, inject + "\n")
    s2 = "".join(lines)
else:
    s2 = inject + "\n" + s

# Now patch the place where renderer decides rid:
# Replace common patterns:
#   const rid = ...;
#   or rid = scrapeRIDFromDOM()...
# We'll add: rid = await window.__vsp_choose_rid_valid();
patts = [
  r'const\s+rid\s*=\s*scrapeRIDFromDOM\(\)\s*;',
  r'let\s+rid\s*=\s*scrapeRIDFromDOM\(\)\s*;',
  r'const\s+rid\s*=\s*scrapeRIDFromDOMnet\(\)\s*;',
]
done = False
for pat in patts:
    s2, n = re.subn(pat, 'let rid = await window.__vsp_choose_rid_valid();', s2, count=1)
    if n:
        done = True
        break

# If not found, fallback: find "rendered rid=" log and inject before it
if not done:
    s2, n = re.subn(r'(console\.log\(\s*"\[VSP\].*?rendered rid=.*?\);\s*)',
                    'rid = await window.__vsp_choose_rid_valid();\n\\1', s2, count=1, flags=re.S)
    if n:
        done = True

if not done:
    raise SystemExit("[ERR] cannot locate rid assignment spot to patch; grep for scrapeRIDFromDOM or rendered rid logs.")

p.write_text(s2, encoding="utf-8")
print("[OK] applied:", marker)
PY

node --check "$JS"
echo "[OK] node --check GateStory OK"

echo
echo "[NEXT] systemctl restart vsp-ui-8910.service && Ctrl+Shift+R /vsp5"
echo "[TIP ] test pin: /vsp5?rid=VSP_CI_RUN_20251219_092640"
