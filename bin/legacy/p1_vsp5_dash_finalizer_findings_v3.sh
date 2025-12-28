#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_finalizer_v3_${TS}"
echo "[BACKUP] ${JS}.bak_finalizer_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_VSP5_DASH_FINALIZER_FINDINGS_V3"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_VSP5_DASH_FINALIZER_FINDINGS_V3
   - force counts from findings_unified.meta.counts_by_severity
   - force findings array from root.items/root.findings or best-scored largest array
   - re-apply UI multiple times to defeat other scripts overwriting
*/
(()=> {
  try{
    if (window.__vsp_p1_dash_finalizer_findings_v3) return;
    window.__vsp_p1_dash_finalizer_findings_v3 = true;
    if (!(location && location.pathname && location.pathname.indexOf("/vsp5")===0)) return;

    const $ = (id)=> document.getElementById(id);
    const ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const W = {CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4,TRACE:5};

    const esc = (s)=> (s==null? "" : String(s)).replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
    const normSev = (v)=>{
      const s = (v||"").toString().toUpperCase();
      if (ORDER.includes(s)) return s;
      if (s==="WARNING") return "MEDIUM";
      if (s==="ERROR") return "HIGH";
      return "INFO";
    };
    const sevBadge = (sev)=> {
      const S = normSev(sev);
      return `<span class="sev_badge sev_${S}">${S}</span>`;
    };

    function scoreArr(arr){
      if (!Array.isArray(arr) || !arr.length) return -1;
      let score = 0;
      const sample = arr.slice(0, 30);
      for (const o of sample){
        if (!o || typeof o !== "object") continue;
        if (o.severity||o.sev||o.level) score += 3;
        if (o.tool||o.scanner||o.engine) score += 2;
        if (o.rule_id||o.rule||o.check_id||o.id) score += 2;
        if (o.location||o.path||o.file||o.file_path) score += 1;
      }
      score += Math.min(arr.length, 5000) / 40; // favor large arrays
      return score;
    }

    function findBestArray(root){
      // direct keys first
      for (const k of ["items","findings","results","data","rows","records"]){
        if (root && Array.isArray(root[k]) && root[k].length) return root[k];
      }
      let best = [];
      const walk=(x, depth)=>{
        if (!x || depth>6) return;
        if (Array.isArray(x)){
          if (scoreArr(x) > scoreArr(best)) best = x;
          return;
        }
        if (typeof x !== "object") return;
        for (const k of Object.keys(x)) walk(x[k], depth+1);
      };
      walk(root, 0);
      return Array.isArray(best) ? best : [];
    }

    function normalizeCountsFromMeta(metaCounts){
      const c = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      if (!metaCounts || typeof metaCounts !== "object") return c;
      for (const k of ORDER) c[k] = Number(metaCounts[k]||0)||0;
      return c;
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
        const a0 = acc, a1 = acc + p; acc = a1;
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

    function renderTop(findings, rid){
      const rows = $("vsp_findings_rows");
      const metaEl = $("vsp_findings_meta");
      if (metaEl) metaEl.textContent = `items=${findings.length} • rid=${rid.slice(0,24)}…`;
      if (!rows) return;

      if (!findings.length){
        rows.innerHTML = `<tr><td colspan="4" style="opacity:.7;">No findings array detected.</td></tr>`;
        return;
      }

      const top = findings.slice().sort((a,b)=>{
        const sa = W[normSev(a?.severity||a?.sev||a?.level)] ?? 9;
        const sb = W[normSev(b?.severity||b?.sev||b?.level)] ?? 9;
        if (sa!==sb) return sa-sb;
        return String(a?.tool||"").localeCompare(String(b?.tool||""));
      }).slice(0, 12);

      rows.innerHTML = top.map(f=>{
        const sev = normSev(f?.severity||f?.sev||f?.level||f?.priority);
        const tool = (f?.tool||f?.scanner||f?.engine||f?.source||"—").toString();
        const title = (f?.title||f?.name||f?.message||f?.desc||f?.description||f?.summary||"—").toString();
        const rule = (f?.rule_id||f?.rule||f?.check_id||f?.id||"").toString();
        const loc  = (f?.location||f?.path||f?.file||f?.file_path||f?.filename||"—").toString();
        const t = rule ? `${title} • ${rule}` : title;
        return `<tr>
          <td>${sevBadge(sev)}</td>
          <td style="opacity:.9;">${esc(tool)}</td>
          <td style="opacity:.92;">${esc(t).slice(0,220)}</td>
          <td style="opacity:.85;font-family:ui-monospace,monospace;font-size:11.5px;">${esc(loc).slice(0,220)}</td>
        </tr>`;
      }).join("");
    }

    async function applyOnce(){
      const meta = await (await fetch("/api/vsp/runs?_ts="+Date.now(), {cache:"no-store"})).json();
      const rid = meta?.rid_latest_gate_root || meta?.rid_latest || meta?.rid_last_good || meta?.rid_latest_findings || "";
      if (!rid) return;

      const r = await fetch(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&_ts=${Date.now()}`, {cache:"no-store"});
      if (!r.ok) return;
      const root = await r.json();

      const counts = normalizeCountsFromMeta(root?.meta?.counts_by_severity);
      const findings = findBestArray(root);

      // If we somehow picked tiny array but meta.max_items is big => force choose root.items/findings if present
      const maxItems = Number(root?.meta?.max_items||0)||0;
      let finalFindings = findings;
      if (finalFindings.length <= 5 && maxItems >= 100){
        if (Array.isArray(root?.items) && root.items.length) finalFindings = root.items;
        else if (Array.isArray(root?.findings) && root.findings.length) finalFindings = root.findings;
      }

      updateKpiPills(counts);
      renderDonut(counts);
      renderTop(finalFindings, rid);

      console.log("[VSP][FinalizerV3] ok rid=", rid, "findings=", finalFindings.length, "counts=", counts);
    }

    // Run multiple times quickly to override other renderers, then keep alive
    let n=0;
    const burst = setInterval(()=>{
      n++;
      applyOnce().catch(()=>{});
      if (n>=8) clearInterval(burst);
    }, 700);

    setInterval(()=> {
      if (document.visibilityState && document.visibilityState !== "visible") return;
      applyOnce().catch(()=>{});
    }, 120000);

    console.log("[VSP][FinalizerV3] installed");
  }catch(e){
    console.warn("[VSP][FinalizerV3] init failed", e);
  }
})();
"""
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended finalizer v3")
PY

node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] HARD reload /vsp5 (Ctrl+Shift+R). Expect: [VSP][FinalizerV3] installed + counts non-zero."
