#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_fix_findings_counts_v2_${TS}"
echo "[BACKUP] ${JS}.bak_fix_findings_counts_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_VSP5_FINDINGS_COUNTS_RENDER_V2"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_VSP5_FINDINGS_COUNTS_RENDER_V2
   - Parse findings_unified.json (your schema: {meta:{counts_by_severity,...}, <array>})
   - Prefer meta.counts_by_severity for donut/KPI
   - Find correct findings array by heuristics (largest array of objects w/ severity/tool/rule_id)
*/
(()=> {
  try{
    if (window.__vsp_p1_findings_counts_render_v2) return;
    window.__vsp_p1_findings_counts_render_v2 = true;
    if (!(location && location.pathname && location.pathname.indexOf("/vsp5")===0)) return;

    const $ = (id)=> document.getElementById(id);
    const esc = (s)=> (s==null? "" : String(s)).replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));

    const ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const W = {CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4,TRACE:5};

    function normSev(v){
      const s = (v||"").toString().toUpperCase();
      if (ORDER.includes(s)) return s;
      if (s==="WARNING") return "MEDIUM";
      if (s==="ERROR") return "HIGH";
      return "INFO";
    }

    function sevBadge(sev){
      const S = normSev(sev);
      return `<span class="sev_badge sev_${S}">${S}</span>`;
    }

    function calcCounts(findings){
      const c = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      for (const f of (findings||[])){
        const sev = normSev(f?.severity || f?.sev || f?.level || f?.priority);
        c[sev] = (c[sev]||0) + 1;
      }
      return c;
    }

    function pickFindingsArray(root){
      if (!root || typeof root !== "object") return [];
      // direct common keys
      for (const k of ["items","findings","results","data","rows","records"]){
        if (Array.isArray(root[k])) return root[k];
      }
      // scan all arrays and pick the "most findings-like"
      let best = [];
      function scoreArr(arr){
        if (!Array.isArray(arr) || !arr.length) return -1;
        let score = 0;
        // prefer array of objects
        const sample = arr.slice(0, 20);
        for (const o of sample){
          if (!o || typeof o !== "object") continue;
          if (o.severity||o.sev||o.level) score += 3;
          if (o.tool||o.scanner||o.engine) score += 2;
          if (o.rule_id||o.rule||o.check_id||o.id) score += 2;
          if (o.location||o.path||o.file||o.file_path) score += 1;
        }
        // weight by size a bit (your file max_items=2500)
        score += Math.min(arr.length, 2500) / 50;
        return score;
      }
      function walk(obj, depth){
        if (!obj || depth>5) return;
        if (Array.isArray(obj)){
          const sc = scoreArr(obj);
          if (sc > scoreArr(best)) best = obj;
          return;
        }
        if (typeof obj !== "object") return;
        for (const k of Object.keys(obj)){
          walk(obj[k], depth+1);
        }
      }
      walk(root, 0);
      return Array.isArray(best) ? best : [];
    }

    function renderDonut(counts){
      const donut = $("vsp_sev_donut");
      const center = $("vsp_sev_total");
      const legend = $("vsp_sev_legend");
      if (!donut || !center || !legend) return;

      const total = ORDER.reduce((a,k)=>a+(counts[k]||0),0) || 0;
      center.textContent = String(total);

      const tint = {
        CRITICAL:"rgba(255,72,72,.55)",
        HIGH:"rgba(255,120,72,.45)",
        MEDIUM:"rgba(255,190,64,.40)",
        LOW:"rgba(140,200,255,.32)",
        INFO:"rgba(190,190,190,.22)",
        TRACE:"rgba(130,130,130,.18)",
      };

      let acc = 0;
      const segs = [];
      legend.innerHTML = "";
      for (const k of ORDER){
        const v = counts[k]||0;
        if (!v) continue;
        const p = total ? (v/total)*100 : 0;
        const a0 = acc, a1 = acc + p;
        acc = a1;
        segs.push(`${tint[k]} ${a0}% ${a1}%`);

        const lg = document.createElement("div");
        lg.className = "lg";
        lg.innerHTML = `<span class="dot" style="background:${tint[k]};"></span>${k}:${v}`;
        legend.appendChild(lg);
      }
      if (!segs.length){
        segs.push("rgba(255,255,255,.10) 0% 100%");
        legend.innerHTML = `<div class="lg" style="opacity:.7;">No counts</div>`;
      }
      donut.style.background = `conic-gradient(${segs.join(",")})`;

      // also update the "No counts found" text if present
      const sevCard = donut.closest(".vsp_card");
      if (sevCard){
        const p = sevCard.querySelector("div[style*='opacity:.72']");
        if (p) p.textContent = total ? `Total findings: ${total}` : `No counts`;
      }
    }

    function updateKpiPills(counts){
      const map = {
        vsp_dash_c_critical: `CRIT:${counts.CRITICAL||0}`,
        vsp_dash_c_high:     `HIGH:${counts.HIGH||0}`,
        vsp_dash_c_medium:   `MED:${counts.MEDIUM||0}`,
        vsp_dash_c_low:      `LOW:${counts.LOW||0}`,
        vsp_dash_c_info:     `INFO:${counts.INFO||0}`,
        vsp_dash_c_trace:    `TRACE:${counts.TRACE||0}`,
      };
      for (const id of Object.keys(map)){
        const el = $(id);
        if (el) el.textContent = map[id];
      }
    }

    function renderTopFindings(findings, rid){
      const rows = $("vsp_findings_rows");
      const metaEl = $("vsp_findings_meta");
      if (metaEl) metaEl.textContent = `items=${findings.length} • rid=${rid.slice(0,24)}…`;
      if (!rows) return;

      if (!findings.length){
        rows.innerHTML = `<tr><td colspan="4" style="opacity:.7;">No findings found in findings_unified.json</td></tr>`;
        return;
      }

      const top = findings.slice().sort((a,b)=>{
        const sa = W[normSev(a?.severity||a?.sev||a?.level)] ?? 9;
        const sb = W[normSev(b?.severity||b?.sev||b?.level)] ?? 9;
        if (sa!==sb) return sa-sb;
        const ta = (a?.tool||a?.scanner||a?.engine||"").toString();
        const tb = (b?.tool||b?.scanner||b?.engine||"").toString();
        return ta.localeCompare(tb);
      }).slice(0, 12);

      rows.innerHTML = top.map(f=>{
        const sev = normSev(f?.severity||f?.sev||f?.level||f?.priority);
        const tool = (f?.tool||f?.scanner||f?.engine||f?.source||"—").toString();
        const title = (f?.title||f?.name||f?.message||f?.desc||f?.description||f?.summary||"—").toString();
        const rule = (f?.rule_id||f?.rule||f?.check_id||f?.id||f?.cwe||f?.owasp||"").toString();
        const loc  = (f?.location||f?.path||f?.file||f?.file_path||f?.filename||"—").toString();
        const t = rule ? `${title} • ${rule}` : title;
        return `<tr>
          <td>${sevBadge(sev)}</td>
          <td style="opacity:.9;">${esc(tool)}</td>
          <td style="opacity:.92;">${esc(t).slice(0,220)}</td>
          <td style="opacity:.85;font-family:ui-monospace,monospace;font-size:11.5px;">${esc(loc).slice(0,200)}</td>
        </tr>`;
      }).join("");
    }

    async function runOnce(){
      const meta = await (await fetch("/api/vsp/runs?_ts="+Date.now(), {cache:"no-store"})).json();
      const rid = meta?.rid_latest_gate_root || meta?.rid_latest || meta?.rid_last_good || meta?.rid_latest_findings || "";
      if (!rid) return;

      const r = await fetch(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&_ts=${Date.now()}`, {cache:"no-store"});
      if (!r.ok) return;
      const txt = await r.text();

      let root = null;
      try{ root = JSON.parse(txt); }catch(e){
        console.warn("[VSP][FindingsV2] JSON.parse failed", e);
        return;
      }

      const counts = (root?.meta && root.meta.counts_by_severity) ? root.meta.counts_by_severity : null;
      const findings = pickFindingsArray(root);

      const c = counts ? {
        CRITICAL:Number(counts.CRITICAL||0)||0,
        HIGH:Number(counts.HIGH||0)||0,
        MEDIUM:Number(counts.MEDIUM||0)||0,
        LOW:Number(counts.LOW||0)||0,
        INFO:Number(counts.INFO||0)||0,
        TRACE:Number(counts.TRACE||0)||0,
      } : calcCounts(findings);

      updateKpiPills(c);
      renderDonut(c);
      renderTopFindings(findings, rid);

      console.log("[VSP][FindingsV2] ok rid=", rid, "findings=", findings.length, "counts=", c);
    }

    setTimeout(()=> runOnce().catch(e=>console.warn("[VSP][FindingsV2] err", e)), 450);
    setInterval(()=> {
      if (document.visibilityState && document.visibilityState !== "visible") return;
      runOnce().catch(()=>{});
    }, 90000);

    console.log("[VSP][FindingsV2] installed");
  }catch(e){
    console.warn("[VSP][FindingsV2] init failed", e);
  }
})();
"""
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended findings counts render v2")
PY

node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] Hard reload /vsp5 (Ctrl+Shift+R). Expect: [VSP][FindingsV2] installed"
