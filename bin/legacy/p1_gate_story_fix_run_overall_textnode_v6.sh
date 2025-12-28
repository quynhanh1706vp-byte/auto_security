#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_gate_overall_v6_${TS}"
echo "[BACKUP] ${JS}.bak_gate_overall_v6_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_RUN_OVERALL_TEXTNODE_FIX_V6"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=r"""
/* VSP_P1_GATE_STORY_RUN_OVERALL_TEXTNODE_FIX_V6
   - Update "Run overall" using TEXT NODE walker (works even if split spans)
   - Reads latest gate from __vsp_gate_latest_v4b (set by V4B) or tries __vsp_gate_latest_v3
*/
(()=> {
  if (window.__vsp_p1_gate_story_run_overall_textnode_fix_v6) return;
  window.__vsp_p1_gate_story_run_overall_textnode_fix_v6 = true;

  const norm = (x)=> (x||"").toString().trim().toUpperCase();
  const STATUSES = ["UNKNOWN","GREEN","AMBER","RED"];

  function getOverall(){
    const g = window.__vsp_gate_latest_v4b || window.__vsp_gate_latest_v3 || window.__vsp_gate_latest_v3 || null;
    return g ? norm(g.overall || g.overall_status) : "";
  }

  function patchTextNodes(ov){
    if (!ov) return 0;
    let n=0;
    try{
      const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
      let node;
      while ((node = w.nextNode())) {
        const t = node.nodeValue || "";
        if (t.includes("Run overall:")) {
          const t2 = t.replace(/Run overall:\s*(UNKNOWN|GREEN|AMBER|RED)/i, "Run overall: " + ov);
          if (t2 !== t) { node.nodeValue = t2; n++; }
        }
      }
    }catch(e){}
    return n;
  }

  function patchSplitSpans(ov){
    if (!ov) return 0;
    let n=0;
    try{
      // Find containers that mention "Run overall" and flip any child that is a status token
      const nodes = Array.from(document.querySelectorAll("*"))
        .filter(el => (el.textContent||"").includes("Run overall"));
      for (const el of nodes.slice(0,30)){
        const kids = el.querySelectorAll("span,div,b,i,strong,small");
        for (const k of kids){
          const tx = norm(k.textContent);
          if (STATUSES.includes(tx)) {
            k.textContent = ov;
            n++;
          }
        }
      }
    }catch(e){}
    return n;
  }

  function tick(){
    const ov = getOverall();
    if (!ov) return;
    const a = patchTextNodes(ov);
    const b = patchSplitSpans(ov);
    // only log once when we successfully patched something
    if ((a+b) > 0 && !window.__vsp_p1_gate_story_run_overall_textnode_fix_v6_logged){
      window.__vsp_p1_gate_story_run_overall_textnode_fix_v6_logged = true;
      console.log("[GateStoryV1] V6 patched Run overall =>", ov, "nodes=", (a+b));
    }
  }

  setInterval(tick, 500);
  setTimeout(tick, 80);
  console.log("[GateStoryV1] V6 installed: Run overall textnode patcher");
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK (post-V6)"
fi

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect: Run overall text becomes RED."
