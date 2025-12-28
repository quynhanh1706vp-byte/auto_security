#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_gate_dom_v3_${TS}"
echo "[BACKUP] ${JS}.bak_gate_dom_v3_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V3"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

addon = r"""
/* VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V3
   - capture gate json from /api/vsp/run_file_allow
   - apply to DOM: Run overall + tool badges (fix UNKNOWN) without relying on internal GateStory code
*/
(()=> {
  if (window.__vsp_p1_gate_story_apply_gate_to_dom_v3) return;
  window.__vsp_p1_gate_story_apply_gate_to_dom_v3 = true;

  const TOOLS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];

  function norm(s){ return (s||"").toString().trim().toUpperCase(); }

  function statusFromCounts(ct){
    ct = ct || {};
    const c = (ct.CRITICAL||0), h=(ct.HIGH||0), m=(ct.MEDIUM||0), l=(ct.LOW||0), i=(ct.INFO||0), t=(ct.TRACE||0);
    if (c+h > 0) return "RED";
    if (m > 0) return "AMBER";
    if (l+i+t > 0) return "GREEN";
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
        // normalize common variants
        if (st === "PASS" || st === "OK" || st === "GREEN") out[k]="GREEN";
        else if (st === "WARN" || st === "AMBER") out[k]="AMBER";
        else if (st === "FAIL" || st === "BLOCK" || st === "RED") out[k]="RED";
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
      .filter(el => (el.childElementCount===0) && /Run overall:/i.test(el.textContent||""));
    for (const el of nodes.slice(0,5)){
      const t = el.textContent || "";
      el.textContent = t.replace(/Run overall:\s*\w+/i, "Run overall: " + ov);
    }
  }

  function applyToolBadges(map){
    const all = Array.from(document.querySelectorAll("button,span,div"))
      .filter(el => (el.childElementCount===0) && (el.textContent||"").length < 60);

    for (const tool of TOOLS){
      const st = map[tool] || "UNKNOWN";
      for (const el of all){
        const txt = (el.textContent||"").trim();
        if (!txt) continue;
        // match "TOOL - XXX" or "TOOL · XXX"
        const re = new RegExp("^\\s*"+tool+"\\s*([\\-·:\\|])\\s*(GREEN|AMBER|RED|UNKNOWN)\\s*$","i");
        if (re.test(txt)){
          el.textContent = txt.replace(re, tool + " $1 " + st);
        }
      }
    }
  }

  function applyGate(gate){
    if (!gate || typeof gate !== "object") return;
    applyRunOverall(gate);
    const map = computeToolStatus(gate);
    applyToolBadges(map);
  }

  // --- capture gate json from fetch ---
  const prevFetch = window.fetch;
  window.fetch = async function(input, init){
    const res = await prevFetch(input, init);
    try{
      const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
      if (url && url.includes("/api/vsp/run_file_allow")){
        // clone + try json
        const c = res.clone();
        c.json().then(j=>{
          if (j && typeof j === "object" && (j.by_tool || j.counts_total || j.overall || j.overall_status)){
            window.__vsp_gate_latest_v3 = j;
            applyGate(j);
          }
        }).catch(()=>{});
      }
    }catch(e){}
    return res;
  };

  // --- periodic apply (in case DOM rerender) ---
  setInterval(()=>{ try{ if (window.__vsp_gate_latest_v3) applyGate(window.__vsp_gate_latest_v3); }catch(e){} }, 1000);

  console.log("[GateStoryV1] V3 apply DOM: Run overall + tool UNKNOWN fill (by_tool)");
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect: Run overall synced + fewer UNKNOWN tool badges."
