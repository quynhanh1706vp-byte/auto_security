#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_lastgood_v9_${TS}"
echo "[BACKUP] ${JS}.bak_lastgood_v9_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_FETCH_FALLBACK_LASTGOOD_V9"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

patch = r"""
/* VSP_P1_GATE_STORY_FETCH_FALLBACK_LASTGOOD_V9
   If latest RID has no gate artifact -> auto fallback to last_good RID stored in localStorage.
*/
(()=> {
  if (window.__vsp_gate_story_lastgood_v9) return;
  window.__vsp_gate_story_lastgood_v9 = true;

  const LS_KEY = "vsp_last_good_gate_rid_v1";

  function isGateUrl(u){
    try{
      const url = new URL(u, window.location.origin);
      if (!url.pathname.includes("/api/vsp/run_file_allow")) return false;
      const path = (url.searchParams.get("path")||"");
      return /run_gate(_summary)?\.json$/i.test(path);
    }catch(e){ return false; }
  }
  function getRid(u){
    try{ return new URL(u, window.location.origin).searchParams.get("rid")||""; }catch(e){ return ""; }
  }
  function setLastGood(rid){
    if (!rid) return;
    try{ localStorage.setItem(LS_KEY, rid); }catch(e){}
  }
  function getLastGood(){
    try{ return localStorage.getItem(LS_KEY)||""; }catch(e){ return ""; }
  }
  function swapRid(u, rid){
    const url = new URL(u, window.location.origin);
    url.searchParams.set("rid", rid);
    return url.toString();
  }

  const _fetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
    if (!url || !isGateUrl(url)) return _fetch(input, init);

    const rid = getRid(url);
    const lastGood = getLastGood();

    // try original
    const r1 = await _fetch(input, init);
    if (r1 && r1.ok) {
      // mark last good on ok
      setLastGood(rid);
      return r1;
    }

    // fallback if we have last good
    if (lastGood && lastGood !== rid) {
      const u2 = swapRid(url, lastGood);
      console.warn("[GateStoryV1][V9] gate fetch failed for rid=", rid, "=> fallback to last_good=", lastGood);
      // NOTE: if input is Request, we rebuild a Request
      if (typeof input === "string") return _fetch(u2, init);
      try{
        const req2 = new Request(u2, input);
        return _fetch(req2, init);
      }catch(e){
        return _fetch(u2, init);
      }
    }

    return r1;
  };

  console.log("[GateStoryV1] V9 installed: fetch fallback to last_good RID");
})();
"""
p.write_text(s + "\n" + patch + "\n", encoding="utf-8")
print("[OK] appended", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 2; }
echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R). If latest RID has no gate, UI will auto fallback to last-good RID."
