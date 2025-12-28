#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_v10_${TS}"
echo "[BACKUP] ${JS}.bak_v10_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_GATE_STORY_AUTOPICK_GATEJSON_HIDE_LEGACY_V10"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

append = r"""
/* VSP_P1_GATE_STORY_AUTOPICK_GATEJSON_HIDE_LEGACY_V10 */
(()=> {
  if (window.__vsp_gate_story_v10) return;
  window.__vsp_gate_story_v10 = true;
  const TAG = "[GateStoryV10]";
  const TOOL_ORDER = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
  const GATE_PATHS = ["run_gate_summary.json","run_gate.json","reports/run_gate_summary.json","reports/run_gate.json"];

  const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));

  function findGatePanel(){
    // find element whose text is exactly "Gate Story", then pick a reasonable container
    const nodes = Array.from(document.querySelectorAll("*"))
      .filter(n => n && n.childElementCount===0 && (n.textContent||"").trim()==="Gate Story");
    for (const n of nodes){
      const box = n.closest("div");
      if (box) return box;
    }
    return document.body;
  }

  function hideLegacyToolStrip(){
    // Hide any block that contains "Tool strip" label + its badge row (next sibling)
    const all = Array.from(document.querySelectorAll("*"));
    for (const el of all){
      const t = (el.textContent||"").trim();
      if (!t) continue;
      if (/^Tool strip\s*\(/i.test(t) || t==="Tool strip" || t.startsWith("Tool strip ")){
        const parent = el.parentElement;
        if (parent) parent.style.display = "none";
        const next = parent ? parent.nextElementSibling : el.nextElementSibling;
        if (next && next.querySelectorAll && next.querySelectorAll("span,button,div").length>=3){
          next.style.display = "none";
        }
      }
    }
    // Also hide the older concatenated strip line if exists (defensive)
    const bad = all.filter(el => (el.textContent||"").includes("BANDIT -") && (el.textContent||"").includes("SEMGREP -") && el.childElementCount===0);
    for (const el of bad){
      const parent = el.parentElement;
      if (parent) parent.style.display = "none";
      else el.style.display = "none";
    }
    console.log(TAG, "hideLegacyToolStrip done");
  }

  async function fetchGateJsonStrict(rid){
    for (const path of GATE_PATHS){
      const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
      let r;
      try{
        r = await fetch(url, {cache:"no-store"});
      }catch(e){
        continue;
      }
      if (!r || !r.ok) continue;

      const ct = (r.headers.get("content-type")||"").toLowerCase();
      if (!ct.includes("application/json")){
        // Important: run_file_allow may "fallback" to SUMMARY.txt as text/plain -> treat as missing
        console.warn(TAG, "non-json gate response => treat missing", {rid, path, ct});
        continue;
      }
      try{
        const j = await r.json();
        if (j && typeof j === "object" && (j.overall || j.overall_status) && (j.by_tool || j.counts_total)){
          return { rid, path, gate: j };
        }
      }catch(e){
        console.warn(TAG, "json parse failed", {rid, path, e});
      }
    }
    return null;
  }

  async function pickLastGoodGate(){
    // scan recent runs and pick the first RID that has real gate JSON
    const runsUrl = "/api/vsp/runs?limit=120&offset=0";
    let data = null;
    try{
      const r = await fetch(runsUrl, {cache:"no-store"});
      if (!r.ok) return null;
      data = await r.json();
    }catch(e){
      return null;
    }
    const items = data?.items || data?.runs || [];
    for (const it of items){
      const rid = it?.run_id || it?.rid || it?.id;
      if (!rid) continue;
      const g = await fetchGateJsonStrict(rid);
      if (g) return g;
      await sleep(10);
    }
    return null;
  }

  function setTextStartsWith(prefix, newText){
    const nodes = Array.from(document.querySelectorAll("*"))
      .filter(n => n && n.childElementCount===0 && ((n.textContent||"").trim().startsWith(prefix)));
    if (nodes[0]) nodes[0].textContent = newText;
  }

  function renderToolTruth(panel, gateObj){
    const overall = (gateObj.overall || gateObj.overall_status || "UNKNOWN");
    const byTool = gateObj.by_tool || {};

    // Update "RID:" and "Run overall:"
    // (RID is on screen already; we update to picked rid in caller)
    setTextStartsWith("Run overall:", `Run overall: ${overall}`);

    // Update the overall pill if we can find it
    const candidates = Array.from(document.querySelectorAll("span,div,button"))
      .filter(n => /^(UNKNOWN|RED|AMBER|GREEN)$/i.test(((n.textContent||"").trim())) );
    // prefer one that lives inside the Gate panel
    const pill = candidates.find(n => panel.contains(n));
    if (pill) pill.textContent = overall;

    // Render a dedicated strip (V10)
    let box = document.getElementById("vsp_gate_story_tool_truth_v10");
    if (!box){
      box = document.createElement("div");
      box.id = "vsp_gate_story_tool_truth_v10";
      box.style.marginTop = "10px";
      box.style.paddingTop = "8px";
      box.style.borderTop = "1px solid rgba(255,255,255,0.10)";
      panel.appendChild(box);
    }
    box.innerHTML = "";

    const title = document.createElement("div");
    title.textContent = "Tool truth (Gate JSON V10):";
    title.style.fontSize = "12px";
    title.style.opacity = "0.85";
    title.style.marginBottom = "6px";
    box.appendChild(title);

    const row = document.createElement("div");
    row.style.display = "flex";
    row.style.flexWrap = "wrap";
    row.style.gap = "6px";
    box.appendChild(row);

    for (const t of TOOL_ORDER){
      const o = byTool[t] || {};
      const v = (o.verdict || o.status || "MISSING");
      const chip = document.createElement("span");
      chip.textContent = `${t}: ${v}`;
      chip.style.padding = "4px 10px";
      chip.style.borderRadius = "999px";
      chip.style.border = "1px solid rgba(255,255,255,0.14)";
      chip.style.fontSize = "12px";
      chip.style.lineHeight = "16px";
      row.appendChild(chip);
    }
  }

  async function main(){
    const panel = findGatePanel();
    hideLegacyToolStrip();

    const picked = await pickLastGoodGate();
    if (!picked){
      console.warn(TAG, "no gate JSON found in recent runs");
      return;
    }

    // Update RID line on screen
    setTextStartsWith("RID:", `RID: ${picked.rid}`);
    console.log(TAG, "picked last-good gate", picked.rid, "path=", picked.path);

    renderToolTruth(panel, picked.gate);
  }

  // run after other patches executed
  setTimeout(main, 250);
})();
"""
p.write_text(s + "\n" + append + "\n", encoding="utf-8")
print("[OK] appended", marker)
PY

node --check "$JS" >/dev/null
echo "[OK] node --check OK"
echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R). Expect: legacy Tool strip hidden + auto-pick last-good RID with real gate JSON."
