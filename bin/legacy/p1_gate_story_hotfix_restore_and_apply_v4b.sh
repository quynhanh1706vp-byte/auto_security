#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "[INFO] target=$JS"

# ---- 1) RESTORE from latest backup (pre-V4) ----
LATEST_BAK="$(ls -1t ${JS}.bak_gate_dom_v4_* 2>/dev/null | head -n1 || true)"
if [ -n "${LATEST_BAK}" ] && [ -f "${LATEST_BAK}" ]; then
  cp -f "${LATEST_BAK}" "${JS}"
  echo "[OK] restored from ${LATEST_BAK}"
else
  echo "[WARN] no .bak_gate_dom_v4_* found; attempting surgical remove V4 block"
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$JS" "${JS}.bak_surgery_${TS}"
  python3 - "$JS" <<'PY'
import sys, re
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
# remove the V4 block if present
s2, n = re.subn(r"/\*\s*VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V4.*?\*/\s*\(\(\)\s*=>\s*\{.*?\}\)\(\);\s*",
                "", s, flags=re.S)
# also remove trailing marker line if any
s2 = re.sub(r"/\*\s*VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V4\s*\*/", "", s2)
p.write_text(s2, encoding="utf-8")
print("[OK] surgery removed blocks:", n)
PY
fi

# Optional syntax check (if node exists)
if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK (post-restore)"
else
  echo "[WARN] node not found; skip node --check"
fi

# ---- 2) APPLY corrected V4B (valid JS) ----
TS2="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_gate_dom_v4b_${TS2}"
echo "[BACKUP] ${JS}.bak_gate_dom_v4b_${TS2}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V4B"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

addon = r"""
/* VSP_P1_GATE_STORY_APPLY_GATE_TO_DOM_V4B
   - fix JS syntax; sync "Run overall" + normalize tool badges using latest gate json
*/
(()=> {
  if (window.__vsp_p1_gate_story_apply_gate_to_dom_v4b) return;
  window.__vsp_p1_gate_story_apply_gate_to_dom_v4b = true;

  const TOOLS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
  const norm = (x)=> (x||"").toString().trim().toUpperCase();

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
      const st0 = norm(o.status || o.overall || o.verdict);
      if (st0 && st0 !== "UNKNOWN"){
        if (st0==="PASS"||st0==="OK"||st0==="GREEN") out[k]="GREEN";
        else if (st0==="WARN"||st0==="AMBER") out[k]="AMBER";
        else if (st0==="FAIL"||st0==="BLOCK"||st0==="RED") out[k]="RED";
        else out[k]=st0;
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
    for (const el of nodes.slice(0,8)){
      try{
        const t = el.textContent || "";
        const t2 = t.replace(/Run overall:\s*[A-Za-z_]+/i, "Run overall: " + ov);
        if (t2 !== t) el.textContent = t2;
      }catch(e){}
    }
  }

  function applyToolBadges(map){
    const nodes = Array.from(document.querySelectorAll("button,span,div"))
      .filter(el => (el.textContent||"").length < 80);

    for (const tool of TOOLS){
      const st = map[tool] || "UNKNOWN";
      const re = new RegExp("^\\s*" + tool + "\\s*([\\-·:\\|])\\s*(GREEN|AMBER|RED|UNKNOWN)\\s*$","i");
      for (const el of nodes){
        const txt = (el.textContent||"").trim();
        if (!txt) continue;
        if (!txt.toUpperCase().includes(tool)) continue;
        if (re.test(txt)){
          el.textContent = txt.replace(re, tool + " $1 " + st);
        }
      }
    }
  }

  function applyGate(gate){
    if (!gate || typeof gate !== "object") return;
    applyRunOverall(gate);
    applyToolBadges(computeToolStatus(gate));
  }

  const prevFetch = window.fetch;
  window.fetch = async function(input, init){
    const res = await prevFetch(input, init);
    try{
      const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
      if (url && url.includes("/api/vsp/run_file_allow")){
        const c = res.clone();
        c.json().then(j=>{
          if (j && typeof j === "object" && (j.by_tool || j.counts_total || j.overall || j.overall_status)){
            window.__vsp_gate_latest_v4b = j;
            applyGate(j);
          }
        }).catch(()=>{});
      }
    }catch(e){}
    return res;
  };

  setInterval(()=>{ try{ if (window.__vsp_gate_latest_v4b) applyGate(window.__vsp_gate_latest_v4b); }catch(e){} }, 900);

  console.log("[GateStoryV1] V4B apply DOM: Run overall + tool badge normalize");
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK (post-V4B)"
fi

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Open /vsp5 and HARD refresh (Ctrl+Shift+R). Expect no SyntaxError."
