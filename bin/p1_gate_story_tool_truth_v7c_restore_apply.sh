#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "[INFO] target=$JS"

# 1) restore from latest pre-V7B backup (the backup taken BEFORE appending V7B)
BAK="$(ls -1t ${JS}.bak_tool_truth_v7b_* 2>/dev/null | head -n1 || true)"
if [ -z "$BAK" ]; then
  echo "[ERR] cannot find ${JS}.bak_tool_truth_v7b_* to restore"
  exit 2
fi

cp -f "$BAK" "$JS"
echo "[OK] restored from $BAK"

# 2) append V7C safe strip renderer
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_tool_truth_v7c_${TS}"
echo "[BACKUP] ${JS}.bak_tool_truth_v7c_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_TOOL_TRUTH_V7C"
if marker in s:
    print("[OK] already has V7C")
    raise SystemExit(0)

addon=r"""
/* VSP_P1_GATE_STORY_TOOL_TRUTH_V7C (SAFE)
   - DO NOT brute-force rewrite random text nodes
   - Render a dedicated strip container + only update single-tool badges
*/
(()=> {
  if (window.__vsp_p1_gate_story_tool_truth_v7c) return;
  window.__vsp_p1_gate_story_tool_truth_v7c = true;

  const TOOLS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
  const TOKENS = ["GREEN","AMBER","RED","UNKNOWN","MISSING","DEGRADED"];
  const norm = (x)=> (x||"").toString().trim().toUpperCase();

  function getGate(){
    return window.__vsp_gate_latest_v4b
        || window.__vsp_gate_latest_v6
        || window.__vsp_gate_latest_v5
        || window.__vsp_gate_latest_v3
        || window.__vsp_gate_latest
        || null;
  }

  function statusFromCounts(ct){
    ct = ct || {};
    const c=(ct.CRITICAL||0), h=(ct.HIGH||0), m=(ct.MEDIUM||0);
    const l=(ct.LOW||0), i=(ct.INFO||0), t=(ct.TRACE||0);
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

  function findGateStoryRoot(){
    // try known hooks first
    let r = document.querySelector("#vsp5") || document.querySelector("#app") || document.body;

    // prefer area around "Gate Story"
    const all = Array.from(document.querySelectorAll("div,section,main,article"));
    for (const el of all){
      const t = (el.textContent||"").trim();
      if (t.startsWith("Gate Story") && t.length < 60) return el.parentElement || el;
    }
    return r;
  }

  function ensureStripContainer(root){
    let box = document.getElementById("vsp_tool_truth_strip_v7c");
    if (box) return box;

    box = document.createElement("div");
    box.id = "vsp_tool_truth_strip_v7c";
    box.style.display = "flex";
    box.style.flexWrap = "wrap";
    box.style.gap = "8px";
    box.style.marginTop = "10px";

    const label = document.createElement("div");
    label.textContent = "Tool truth (V7C):";
    label.style.opacity = "0.85";
    label.style.fontSize = "12px";
    label.style.marginRight = "10px";
    label.style.alignSelf = "center";

    const row = document.createElement("div");
    row.id = "vsp_tool_truth_strip_v7c_row";
    row.style.display = "flex";
    row.style.flexWrap = "wrap";
    row.style.gap = "8px";

    box.appendChild(label);
    box.appendChild(row);

    // insert near the existing "Tool strip (8)" line if possible
    const nodes = Array.from(document.querySelectorAll("div,span,p"));
    let anchor = null;
    for (const el of nodes){
      const tx=(el.textContent||"").trim();
      if (/^Tool strip/i.test(tx)) { anchor = el; break; }
    }
    if (anchor && anchor.parentElement){
      anchor.parentElement.appendChild(box);
    } else {
      root.appendChild(box);
    }
    return box;
  }

  function pill(tool, st){
    const b = document.createElement("span");
    b.textContent = `${tool} - ${st}`;
    b.setAttribute("data-vsp-tool", tool);
    b.setAttribute("data-vsp-status", st);
    b.style.padding = "4px 10px";
    b.style.borderRadius = "999px";
    b.style.fontSize = "12px";
    b.style.border = "1px solid rgba(255,255,255,0.12)";
    b.style.background = "rgba(255,255,255,0.04)";
    b.style.userSelect = "text";
    return b;
  }

  function renderStrip(mp){
    const root = findGateStoryRoot();
    const box = ensureStripContainer(root);
    const row = document.getElementById("vsp_tool_truth_strip_v7c_row");
    if (!row) return;

    // rebuild row
    row.innerHTML = "";
    for (const tool of TOOLS){
      row.appendChild(pill(tool, mp[tool] || "UNKNOWN"));
    }
  }

  function fixSingleToolBadges(mp){
    // only touch elements that look like EXACTLY one tool badge
    const els = Array.from(document.querySelectorAll("button,span,div,a"));
    for (const el of els){
      const txt = (el.textContent||"").trim();
      if (!txt || txt.length > 40) continue;

      // skip if contains 2+ tool keywords
      let hits = 0;
      for (const t of TOOLS) if (txt.toUpperCase().includes(t)) hits++;
      if (hits != 1) continue;

      for (const tool of TOOLS){
        if (!txt.toUpperCase().includes(tool)) continue;
        const st = mp[tool] || "UNKNOWN";

        const re1 = new RegExp("^\\s*"+tool+"\\s*[-:·\\|]\\s*("+TOKENS.join("|")+")\\s*$","i");
        const re2 = new RegExp("^\\s*"+tool+"\\s*$","i");
        if (re1.test(txt)) el.textContent = txt.replace(re1, tool+" - "+st);
        else if (re2.test(txt)) el.textContent = tool+" - "+st;
        el.setAttribute("data-vsp-status", st);
      }
    }
  }

  let lastSig = "";
  function tick(){
    const g = getGate();
    if (!g) return;
    const mp = computeToolMap(g);

    renderStrip(mp);
    fixSingleToolBadges(mp);

    const sig = JSON.stringify(mp);
    if (sig !== lastSig){
      lastSig = sig;
      console.log("[GateStoryV1] V7C tool truth:", mp);
    }
  }

  setTimeout(tick, 120);
  setInterval(tick, 1200);
  console.log("[GateStoryV1] V7C installed: safe tool truth strip renderer");
})();
"""

p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK (post-V7C)"
fi

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Open /vsp5 and HARD refresh (Ctrl+Shift+R). Expect: Tool truth (V7C) strip appears + no concatenated text."
