#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_gate_autofetch_v5_${TS}"
echo "[BACKUP] ${JS}.bak_gate_autofetch_v5_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_GATE_STORY_AUTOFETCH_GATE_V5"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

addon = r"""
/* VSP_P1_GATE_STORY_AUTOFETCH_GATE_V5
   - poll /api/vsp/runs -> get latest rid -> fetch /api/vsp/run_file_allow?rid=...&path=run_gate.json
   - triggers existing DOM apply hooks (V3/V4B) because run_file_allow fetch happens
*/
(()=> {
  if (window.__vsp_p1_gate_story_autofetch_gate_v5) return;
  window.__vsp_p1_gate_story_autofetch_gate_v5 = true;

  const BASE = ""; // same-origin
  const RUNS_URL = BASE + "/api/vsp/runs?limit=1&offset=0";
  const POLL_MS = 8000;

  let lastRid = "";
  let inflight = false;

  async function fetchJson(url){
    const r = await fetch(url, { cache: "no-store" });
    if (!r.ok) throw new Error("HTTP "+r.status+" "+url);
    return await r.json();
  }

  async function tick(){
    if (document.hidden) return;
    if (inflight) return;
    inflight = true;
    try{
      const j = await fetchJson(RUNS_URL);
      const it = (j && j.items && j.items[0]) ? j.items[0] : {};
      const rid = (it.rid || it.run_id || "").toString();
      if (rid && rid !== lastRid){
        lastRid = rid;
        const gateUrl = BASE + "/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) +
                        "&path=" + encodeURIComponent("run_gate.json");
        console.log("[GateStoryV1] V5 fetch gate:", rid);
        // this will be captured by V3/V4B fetch hook and applied to DOM
        fetch(gateUrl, { cache: "no-store" }).catch(()=>{});
      }
    }catch(e){
      console.warn("[GateStoryV1] V5 tick err:", e && e.message ? e.message : e);
    }finally{
      inflight = false;
    }
  }

  // kick immediately + interval
  setTimeout(tick, 50);
  setInterval(tick, POLL_MS);

  console.log("[GateStoryV1] V5 installed: auto-fetch run_gate.json from latest RID");
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK (post-V5)"
fi

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect: V5 fetch gate log + Run overall synced."
