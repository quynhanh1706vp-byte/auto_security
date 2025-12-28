#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_force_render_${TS}"
echo "[BACKUP] ${JS}.bak_force_render_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_DASHONLY_FORCE_RENDER_GATE_SUMMARY_V1"
if marker in s:
    print("[OK] marker already present, skip append")
else:
    patch = r"""
/* ===================== VSP_P0_DASHONLY_FORCE_RENDER_GATE_SUMMARY_V1 ===================== */
(()=> {
  if (window.__vsp_p0_dashonly_force_render_v1) return;
  window.__vsp_p0_dashonly_force_render_v1 = true;

  const $ = (sel)=> document.querySelector(sel);
  const esc = (x)=> String(x ?? "").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));

  const setTextAny = (ids, val)=>{
    for (const id of ids){
      const el = document.querySelector(id);
      if (el){ el.textContent = (val==null? "—" : String(val)); return true; }
    }
    return false;
  };

  const normKey = (k)=> String(k||"").toLowerCase().replace(/[^a-z0-9]+/g,"");
  const statusOf = (v)=>{
    if (v == null) return "UNKNOWN";
    if (typeof v === "string") return v.toUpperCase();
    if (typeof v === "boolean") return v ? "OK" : "FAIL";
    if (typeof v === "object"){
      const cand = v.status ?? v.state ?? v.result ?? v.verdict ?? v.outcome;
      if (typeof cand === "string") return cand.toUpperCase();
      if (typeof cand === "boolean") return cand ? "OK" : "FAIL";
      if (v.ok === true) return "OK";
      if (v.missing === true) return "MISSING";
      if (v.degraded === true) return "DEGRADED";
    }
    return "UNKNOWN";
  };

  const applySummary = (sum)=>{
    if (!sum || typeof sum !== "object") return;

    const c = sum.counts_total || sum.counts_by_severity || sum.counts || {};
    const CRIT  = c.CRITICAL ?? c.critical;
    const HIGH  = c.HIGH ?? c.high;
    const MED   = c.MEDIUM ?? c.medium;
    const LOW   = c.LOW ?? c.low;
    const INFO  = c.INFO ?? c.info;
    const TRACE = c.TRACE ?? c.trace;

    let TOTAL = c.TOTAL ?? c.total;
    if (TOTAL == null){
      const nums = [CRIT,HIGH,MED,LOW,INFO,TRACE].map(x=> (x==null? 0 : Number(x)||0));
      TOTAL = nums.reduce((a,b)=>a+b,0);
    }

    // KPI ids: try multiple common ids (không đúng thì bỏ qua)
    setTextAny(["#k_total","#kpi_total","#total_val","[data-kpi='TOTAL']"], TOTAL);
    setTextAny(["#k_crit","#kpi_crit","[data-kpi='CRITICAL']"], CRIT);
    setTextAny(["#k_high","#kpi_high","[data-kpi='HIGH']"], HIGH);
    setTextAny(["#k_med","#kpi_med","[data-kpi='MEDIUM']"], MED);
    setTextAny(["#k_low","#kpi_low","[data-kpi='LOW']"], LOW);
    setTextAny(["#k_info","#kpi_info","[data-kpi='INFO']"], INFO);
    setTextAny(["#k_trace","#kpi_trace","[data-kpi='TRACE']"], TRACE);

    // Tool lane
    const toolsBox = $("#tools_box");
    if (toolsBox){
      const raw = sum.by_tool || sum.byTool || {};
      const normMap = {};
      try{ for (const [k,v] of Object.entries(raw||{})) normMap[normKey(k)] = v; }catch(_e){}

      const pick = (toolName)=>{
        const variants = [
          normKey(toolName),
          normKey(toolName.replace("CodeQL","codeql")),
          normKey(toolName+"_summary"),
          normKey(toolName+"Summary"),
        ];
        for (const k of variants){
          if (k && (k in normMap)) return normMap[k];
        }
        // fallback: try contains
        for (const [k,v] of Object.entries(normMap)){
          if (k.includes(normKey(toolName))) return v;
        }
        return null;
      };

      const order = ["Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","Bandit","CodeQL"];
      toolsBox.innerHTML = order.map(t=>{
        const v = pick(t);
        const st = statusOf(v);
        const cls = (st==="OK" || st==="GREEN") ? "s-ok"
                  : (st==="MISSING" || st==="DEGRADED" || st==="AMBER") ? "s-miss"
                  : (st==="FAIL" || st==="ERROR" || st==="RED") ? "s-bad"
                  : "";
        // normalize display: GREEN->OK, RED->FAIL (optional)
        const disp = (st==="GREEN") ? "OK" : (st==="RED") ? "FAIL" : st;
        return `<div class="tool"><div class="t">${esc(t)}</div><div class="s ${cls}">${esc(disp)}</div></div>`;
      }).join("");
    }

    // Notes (optional)
    const notes = $("#notes_box");
    if (notes){
      // keep existing content, but ensure source line present
      if (!notes.textContent.includes("run_gate_summary")){
        notes.textContent = "Source: run_gate_summary.json (tool truth). No legacy auto-fetch /api/vsp/runs (dash-only).";
      }
    }
  };

  async function fetchJSON(url){
    const r = await fetch(url, {cache:"no-store"});
    if (!r.ok) throw new Error("HTTP "+r.status);
    return await r.json();
  }

  async function loadOnce(){
    try{
      const meta = await fetchJSON("/api/vsp/rid_latest_gate_root");
      const rid = meta && meta.rid;
      if (!rid) return;
      // show RID if input exists
      setTextAny(["#rid_val","#rid_text","#rid_label"], rid);

      const sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`);
      applySummary(sum);
    }catch(e){
      // silent (dash-only should not spam)
      console.warn("[VSP][DASH_ONLY] gate_summary fetch failed:", e && e.message ? e.message : e);
    }
  }

  // run now + periodic (30s)
  loadOnce();
  setInterval(loadOnce, 30000);

  console.log("[VSP][DASH_ONLY] force-render gate_summary enabled");
})();
/* ===================== /VSP_P0_DASHONLY_FORCE_RENDER_GATE_SUMMARY_V1 ===================== */
"""
    s = s.rstrip() + "\n\n" + patch + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended force-render patch block")
PY

echo "== restart service (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "== quick verify endpoints =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 200; echo
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("rid",""))' 2>/dev/null || true)"
if [ -n "$RID" ]; then
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -c 260; echo
fi

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Tool lane should stop showing UNKNOWN/[object Object]."
