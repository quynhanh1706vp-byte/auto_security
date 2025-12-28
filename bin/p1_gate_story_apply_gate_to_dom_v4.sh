#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_gate_dom_v4_${TS}"
echo "[BACKUP] ${JS}.bak_gate_dom_v4_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V4"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

addon = r"""
/* VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V4
   - stronger DOM matcher: updates Run overall even if element has children
   - updates tool badges by contains(tool) + replace trailing status token
*/
(()=> {
  if (window.__vsp_p1_gate_story_apply_gate_to_dom_v4) return;
  window.__vsp_p1_gate_story_apply_gate_to_dom_v4 = true;

  const TOOLS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];

  function norm(s){ return (s||"").toString().trim().toUpperCase(); }

  function statusFromCounts(ct){
    ct = ct || {};
    const c=(ct.CRITICAL||0), h=(ct.HIGH||0), m=(ct.MEDIUM||0), l=(ct.LOW||0), i=(ct.INFO||0), t=(ct.TRACE||0);
    if (c+h>0) return "RED";
    if (m>0) return "AMBER";
    if (l+i+t>0) return "GREEN";
    return "UNKNOWN";
  }

  function computeToolStatus(gate){
    const out = {};
    const bt = (gate && gate.by_tool) ? gate.by_tool : {};
    for (const k of TOOLS){
      const o = bt[k] || bt[k.toLowerCase()] || null;
      if (!o){ out[k]="UNKNOWN"; continue; }
      const st = norm(o.status || o.overall || o.verdict);
      if (st && st !== "UNKNOWN"){
        if (st==="PASS"||st==="OK"||st==="GREEN") out[k]="GREEN";
        else if (st==="WARN"||st==="AMBER") out[k]="AMBER";
        else if (st==="FAIL"||st==="BLOCK"||st==="RED") out[k]="RED";
        else out[k]=st;
      } else {
        const ct = o.counts_total || o.counts || o.totals || {};
        out[k] = statusFromCounts(ct);
      }
    }
    return out;
  }

  function applyRunOverall(gate){
    const ov = norm(gate && (gate.overall || gate.overall_status));
    if (!ov) return;

    const nodes = Array.from(document.querySelectorAll("*"))
      .filter(el => (el.textContent||"").includes("Run overall:"))
      .sort((a,b)=> (a.textContent||"").length - (b.textContent||"").length);

    // update shortest matches first (usually the real label line)
    for (const el of nodes.slice(0,8)){
      try{
        const t = el.textContent || "";
        const t2 = t.replace(/Run overall:\s*[A-Za-z_]+/i, "Run overall: " + ov);
        if (t2 !== t){
          // If element has children, rewrite only text nodes by setting textContent (safe for this label line)
          el.textContent = t2;
        }
      }catch(e){}
    }
  }

  function applyToolBadges(map){
    const nodes = Array.from(document.querySelectorAll("button,span,div"))
      .filter(el => (el.textContent||"").length < 80);

    for (const tool of TOOLS){
      const st = map[tool] || "UNKNOWN";
      for (const el of nodes){
        const txt = (el.textContent||"").trim();
        if (!txt) continue;
        if (!txt.toUpperCase().includes(tool)) continue;

        // normalize patterns like: "TOOL - UNKNOWN" / "TOOL · UNKNOWN" / "TOOL : UNKNOWN"
        const t2 = txt.replace(new RegExp(tool + r"\s*([\\-·:\\|])\s*(GREEN|AMBER|RED|UNKNOWN)\\s*$","i"),
                               tool + " $1 " + st);
        if (t2 !== txt){
          el.textContent = t2;
        }
      }
    }
  }

  function applyGate(gate){
    if (!gate || typeof gate !== "object") return;
    applyRunOverall(gate);
    const m = computeToolStatus(gate);
    applyToolBadges(m);
  }

  // capture from fetch (keep V3 behavior but stronger)
  const prevFetch = window.fetch;
  window.fetch = async function(input, init){
    const res = await prevFetch(input, init);
    try{
      const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
      if (url && url.includes("/api/vsp/run_file_allow")){
        const c = res.clone();
        c.json().then(j=>{
          if (j && typeof j === "object" && (j.by_tool || j.counts_total || j.overall || j.overall_status)){
            window.__vsp_gate_latest_v4 = j;
            applyGate(j);
          }
        }).catch(()=>{});
      }
    }catch(e){}
    return res;
  };

  setInterval(()=>{ try{ if (window.__vsp_gate_latest_v4) applyGate(window.__vsp_gate_latest_v4); }catch(e){} }, 800);

  console.log("[GateStoryV1] V4 apply DOM: Run overall hard-match + tool badges normalize");
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect: Run overall becomes RED, tool UNKNOWN reduced."
