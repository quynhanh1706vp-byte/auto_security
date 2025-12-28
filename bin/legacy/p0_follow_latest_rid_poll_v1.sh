#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

F="static/js/vsp_tabs3_common_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_followlatest_${TS}"
echo "[BACKUP] ${F}.bak_followlatest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_tabs3_common_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_FOLLOW_LATEST_RID_POLL_V1"
if marker in s:
    print("[INFO] marker already present; no change")
    raise SystemExit(0)

inject = textwrap.dedent(r"""
/* VSP_FOLLOW_LATEST_RID_POLL_V1
   - maintain a single RID state shared across tabs
   - optional follow-latest mode (poll /api/vsp/runs?limit=1)
   - dispatch event: vsp:rid_changed {rid, prevRid, reason}
*/
(()=> {
  try {
    if (window.__vsp_follow_latest_rid_poll_v1) return;
    window.__vsp_follow_latest_rid_poll_v1 = true;

    const STATE_KEY = "vsp_follow_latest_rid";
    const saved = (()=>{ try { return JSON.parse(localStorage.getItem(STATE_KEY)||"{}"); } catch(e){ return {}; } })();

    window.__vsp_rid_state = window.__vsp_rid_state || {
      currentRid: saved.currentRid || "",
      followLatest: (saved.followLatest !== undefined) ? !!saved.followLatest : true,
      lastLatestRid: "",
      lastPollAt: 0,
    };

    function saveState(){
      try {
        localStorage.setItem(STATE_KEY, JSON.stringify({
          currentRid: window.__vsp_rid_state.currentRid || "",
          followLatest: !!window.__vsp_rid_state.followLatest
        }));
      } catch(e) {}
    }

    function setRid(newRid, reason){
      const st = window.__vsp_rid_state;
      if(!newRid || typeof newRid !== "string") return;
      if(newRid === st.currentRid) return;
      const prev = st.currentRid;
      st.currentRid = newRid;
      saveState();
      try{
        window.dispatchEvent(new CustomEvent("vsp:rid_changed", {detail:{rid:newRid, prevRid:prev, reason:reason||"set"}}));
      }catch(e){}
    }

    // Expose helper for other JS
    window.__vsp_set_rid = setRid;
    window.__vsp_save_rid_state = saveState;

    async function pollLatest(){
      const st = window.__vsp_rid_state;
      st.lastPollAt = Date.now();
      try{
        const r = await fetch("/api/vsp/runs?limit=1");
        if(!r.ok) return;
        const j = await r.json();
        const runs = j && (j.runs || j.items || j.data) || [];
        const latest = runs && runs[0] && (runs[0].rid || runs[0].run_id || runs[0].id) || "";
        if(latest && typeof latest === "string"){
          st.lastLatestRid = latest;
          if(st.followLatest){
            setRid(latest, "poll_latest");
          }
        }
      }catch(e){}
    }

    // UI toggle (no HTML edits): Alt+L to toggle followLatest
    window.addEventListener("keydown", (ev)=>{
      if(ev.altKey && (ev.key === "l" || ev.key === "L")){
        window.__vsp_rid_state.followLatest = !window.__vsp_rid_state.followLatest;
        saveState();
        try{ console.log("[VSP] followLatest =", window.__vsp_rid_state.followLatest); }catch(e){}
        if(window.__vsp_rid_state.followLatest) pollLatest();
      }
    }, {passive:true});

    // Start polling
    pollLatest();
    setInterval(pollLatest, 15000);
  } catch(e) {}
})();
""")

# inject near top (after first IIFE opener if possible)
m = re.search(r'(\(\s*\)\s*=>\s*\{\s*)', s)
if m:
    pos = m.end()
    s2 = s[:pos] + "\n" + inject + "\n" + s[pos:]
else:
    s2 = inject + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] injected", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check: $F"
echo "[DONE] Ctrl+F5, then try Alt+L to toggle FollowLatest. Listen event vsp:rid_changed."
