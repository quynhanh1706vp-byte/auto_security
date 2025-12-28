#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"

FILES=(
  static/js/vsp_tabs3_common_v3.js
  static/js/vsp_p0_fetch_shim_v1.js
)

echo "== [0] check files =="
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  echo "[OK] $f"
done

echo "== [1] backup =="
for f in "${FILES[@]}"; do
  cp -f "$f" "${f}.bak_rid_verified_autorefresh_${TS}"
  echo "[BACKUP] ${f}.bak_rid_verified_autorefresh_${TS}"
done

echo "== [2] patch (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap

MARKER = "VSP_RID_LATEST_VERIFIED_AUTOREFRESH_V1"

INJECT = textwrap.dedent(r"""
/* VSP_RID_LATEST_VERIFIED_AUTOREFRESH_V1
   - Poll latest RID but ONLY accept RID that has run_gate_summary.json ok=true
   - Emit event: vsp:rid_changed
   - Auto refresh pages on RID change (safe: don't reload while typing)
*/
(()=> {
  try {
    if (window.__vsp_rid_latest_verified_autorefresh_v1) return;
    window.__vsp_rid_latest_verified_autorefresh_v1 = true;

    const STATE_KEY = "vsp_rid_state_v1";
    const saved = (()=>{ try { return JSON.parse(localStorage.getItem(STATE_KEY)||"{}"); } catch(e){ return {}; } })();

    window.__vsp_rid_state = window.__vsp_rid_state || {
      currentRid: saved.currentRid || "",
      followLatest: (saved.followLatest !== undefined) ? !!saved.followLatest : true,
      lastLatestRid: "",
      lastOkRid: saved.lastOkRid || "",
      pendingReload: false,
    };

    function saveState(){
      try{
        localStorage.setItem(STATE_KEY, JSON.stringify({
          currentRid: window.__vsp_rid_state.currentRid || "",
          followLatest: !!window.__vsp_rid_state.followLatest,
          lastOkRid: window.__vsp_rid_state.lastOkRid || ""
        }));
      }catch(e){}
    }

    function isTyping(){
      const a = document.activeElement;
      if(!a) return false;
      const tag = (a.tagName||"").toLowerCase();
      if(tag === "input" || tag === "textarea" || tag === "select") return true;
      if(a.isContentEditable) return true;
      // common editors
      const cls = (a.className||"").toString();
      if(cls.includes("cm-content") || cls.includes("monaco")) return true;
      return false;
    }

    function emitRidChanged(newRid, prevRid, reason){
      try{
        window.dispatchEvent(new CustomEvent("vsp:rid_changed", {detail:{rid:newRid, prevRid, reason}}));
      }catch(e){}
    }

    function setRid(newRid, reason){
      const st = window.__vsp_rid_state;
      if(!newRid || typeof newRid !== "string") return;
      if(newRid === st.currentRid) return;
      const prev = st.currentRid;
      st.currentRid = newRid;
      saveState();
      emitRidChanged(newRid, prev, reason || "set");
    }

    window.__vsp_getRid = function(){
      const st = window.__vsp_rid_state;
      if(st && st.currentRid) return st.currentRid;
      // fallback: query param rid
      try{
        const u = new URL(location.href);
        return u.searchParams.get("rid") || "";
      }catch(e){ return ""; }
    };
    window.__vsp_setRid = setRid;

    async function verifyRidHasGateSummary(rid){
      try{
        const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`;
        const r = await fetch(url);
        if(!r.ok) return False;
        const j = await r.json();
        return !!(j && j.ok);
      }catch(e){
        return False;
      }
    }

    async function pollLatestVerified(){
      const st = window.__vsp_rid_state;
      if(!st.followLatest) return;

      try{
        const r = await fetch("/api/vsp/runs?limit=10");
        if(!r.ok) return;
        const j = await r.json();
        const runs = (j && (j.runs || j.items || j.data)) || [];
        const cands = [];
        for(const it of runs){
          const rid = (it && (it.rid || it.run_id || it.id)) || "";
          if(rid && typeof rid === "string") cands.push(rid);
        }
        if(!cands.length) return;

        // try candidates until one passes verify
        for(const rid of cands){
          st.lastLatestRid = rid;
          const ok = await verifyRidHasGateSummary(rid);
          if(ok){
            st.lastOkRid = rid;
            saveState();
            setRid(rid, "poll_latest_verified");
            return;
          }
        }

        // if none ok, do nothing (keep current rid)
      }catch(e){}
    }

    // Auto refresh on rid change (ALL tabs)
    const refreshable = new Set(["/vsp5","/data_source","/rule_overrides","/settings"]);
    function maybeReload(){
      if(!refreshable.has(location.pathname)) return;
      if(isTyping()){
        window.__vsp_rid_state.pendingReload = true;
        return;
      }
      setTimeout(()=>{ try{ location.reload(); }catch(e){} }, 250);
    }

    window.addEventListener("vsp:rid_changed", (ev)=>{
      try{
        // only reload when followLatest is on
        if(window.__vsp_rid_state && window.__vsp_rid_state.followLatest){
          maybeReload();
        }
      }catch(e){}
    });

    // If user stopped typing and we had pending reload, reload on blur/focusout
    window.addEventListener("focusout", ()=>{
      try{
        const st = window.__vsp_rid_state;
        if(st && st.pendingReload && !isTyping()){
          st.pendingReload = false;
          setTimeout(()=>{ try{ location.reload(); }catch(e){} }, 200);
        }
      }catch(e){}
    });

    // Hotkey: Alt+L toggle followLatest
    window.addEventListener("keydown", (ev)=>{
      if(ev.altKey && (ev.key==="l" || ev.key==="L")){
        ev.preventDefault();
        const st = window.__vsp_rid_state;
        st.followLatest = !st.followLatest;
        saveState();
        try{ console.log("[VSP] followLatest =", st.followLatest); }catch(e){}
        if(st.followLatest) pollLatestVerified();
      }
    }, {passive:false});

    // Start
    pollLatestVerified();
    setInterval(pollLatestVerified, 15000);

  } catch(e) {}
})();
""")

def inject_into(js_path: Path):
  s = js_path.read_text(encoding="utf-8", errors="replace")
  if MARKER in s:
    print("[INFO] already:", js_path)
    return False

  # Inject after first IIFE opener if present, else prepend
  m = re.search(r'(\(\s*\)\s*=>\s*\{\s*)', s)
  if m:
    pos = m.end()
    s2 = s[:pos] + "\n" + INJECT + "\n" + s[pos:]
  else:
    s2 = INJECT + "\n" + s

  js_path.write_text(s2, encoding="utf-8")
  print("[OK] patched:", js_path)
  return True

changed = 0
for f in ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_p0_fetch_shim_v1.js"]:
  p = Path(f)
  if p.exists():
    if inject_into(p):
      changed += 1

print("[DONE] changed:", changed)
PY

echo "== [3] node --check =="
for f in "${FILES[@]}"; do
  node --check "$f" >/dev/null && echo "[OK] node --check: $f"
done

echo "[DONE] Ctrl+F5 all tabs. followLatest toggle: Alt+L. Poll interval 15s (verified RID only)."
