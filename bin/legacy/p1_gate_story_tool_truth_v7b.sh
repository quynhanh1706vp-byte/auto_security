#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_tool_truth_v7b_${TS}"
echo "[BACKUP] ${JS}.bak_tool_truth_v7b_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_TOOL_TRUTH_V7B"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=r"""
/* VSP_P1_GATE_STORY_TOOL_TRUTH_V7B
   - Tool strip must follow by_tool verdict/status (not overall)
   - Source gate: __vsp_gate_latest_v4b (and friends)
*/
(()=> {
  if (window.__vsp_p1_gate_story_tool_truth_v7b) return;
  window.__vsp_p1_gate_story_tool_truth_v7b = true;

  const TOOLS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
  const TOKENS = ["GREEN","AMBER","RED","UNKNOWN","MISSING","DEGRADED"];
  const norm = (x)=> (x||"").toString().trim().toUpperCase();

  function getGate(){
    return window.__vsp_gate_latest_v4b
        || window.__vsp_gate_latest_v6
        || window.__vsp_gate_latest_v5
        || window.__vsp_gate_latest_v3
        || window.__vsp_gate_latest
        || window.__vsp_gate_latest_v7
        || null;
  }

  function statusFromCounts(ct){
    ct = ct || {};
    const c=(ct.CRITICAL||0), h=(ct.HIGH||0), m=(ct.MEDIUM||0), l=(ct.LOW||0), i=(ct.INFO||0), t=(ct.TRACE||0);
    if (c+h>0) return "RED";
    if (m>0) return "AMBER";
    if (l+i+t>0) return "GREEN";
    return "UNKNOWN";
  }

  function mapVerdict(x){
    x = norm(x);
    if (!x) return "";
    if (["OK","PASS","GREEN"].includes(x)) return "GREEN";
    if (["WARN","WARNING","AMBER"].includes(x)) return "AMBER";
    if (["FAIL","FAILED","BLOCK","BLOCKED","ERROR","RED"].includes(x)) return "RED";
    if (TOKENS.includes(x)) return x;
    return x;
  }

  function computeToolMap(gate){
    const out = {};
    const bt = (gate && gate.by_tool) ? gate.by_tool : {};
    for (const tool of TOOLS){
      const o = bt[tool] || bt[tool.toLowerCase()] || null;
      if (!o){ out[tool] = "MISSING"; continue; }

      const degraded = !!(o.degraded || o.timeout || o.timed_out || o.time_out);
      if (degraded){ out[tool] = "DEGRADED"; continue; }

      let st = mapVerdict(o.verdict || o.status || o.overall || o.verdict_status);
      if (!st || st==="UNKNOWN"){
        st = statusFromCounts(o.counts || o.counts_total || o.totals || {});
      }
      out[tool] = st || "UNKNOWN";
    }
    return out;
  }

  function applyToolBadges(mp){
    const els = Array.from(document.querySelectorAll("button,span,div")).filter(el => (el.textContent||"").length < 120);
    for (const tool of TOOLS){
      const st = mp[tool] || "UNKNOWN";
      const re = new RegExp("^\\s*"+tool+"\\s*([\\-·:\\|])\\s*("+TOKENS.join("|")+")\\s*$","i");
      for (const el of els){
        const txt = (el.textContent||"").trim();
        if (!txt) continue;
        if (!txt.toUpperCase().includes(tool)) continue;

        if (re.test(txt)){
          el.textContent = txt.replace(re, tool+" $1 "+st);
          el.setAttribute("data-vsp-status", st);
        } else {
          for (const tk of TOKENS){
            const r2 = new RegExp("\\b"+tk+"\\b\\s*$","i");
            if (r2.test(txt)){
              el.textContent = txt.replace(r2, st);
              el.setAttribute("data-vsp-status", st);
              break;
            }
          }
        }
      }
    }
  }

  let lastSig = "";
  function tick(){
    const g = getGate();
    if (!g) return;
    const mp = computeToolMap(g);
    applyToolBadges(mp);

    // log only when something changes
    const sig = JSON.stringify(mp);
    if (sig !== lastSig){
      lastSig = sig;
      console.log("[GateStoryV1] V7B tool truth:", mp);
    }
  }

  setTimeout(tick, 80);
  setInterval(tick, 800);
  console.log("[GateStoryV1] V7B installed: tool strip uses verdict/status");
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK (post-V7B)"
fi

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Look for console: V7B tool truth."
