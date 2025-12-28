#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_bypass_rewrite_v4_${TS}"
echo "[BACKUP] ${JS}.bak_bypass_rewrite_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_FINDINGS_BYPASS_REWRITE_V4"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_FINDINGS_BYPASS_REWRITE_V4
   - Use iframe.contentWindow.fetch (native) to bypass any wrapped fetch/rewrite
   - Load findings_unified.json correctly => meta.counts_by_severity + items[]
   - Render KPI + donut + Top Findings
*/
(()=> {
  try{
    if (window.__vsp_p1_findings_bypass_rewrite_v4) return;
    window.__vsp_p1_findings_bypass_rewrite_v4 = true;
    if (!(location && location.pathname && location.pathname.indexOf("/vsp5")===0)) return;

    const ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const W = {CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4,TRACE:5};

    const $ = (id)=> document.getElementById(id);
    const esc = (s)=> (s==null? "" : String(s)).replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
    const normSev = (v)=>{
      const s = (v||"").toString().toUpperCase();
      if (ORDER.includes(s)) return s;
      if (s==="WARNING") return "MEDIUM";
      if (s==="ERROR") return "HIGH";
      return "INFO";
    };
    const sevBadge = (sev)=>{
      const S = normSev(sev);
      return `<span class="sev_badge sev_${S}">${S}</span>`;
    };

    function countsFromMeta(metaCounts){
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
        lg.innerHTML = `<span class="dot" style="display:inline-block;width:10px;height:10px;border-radius:999px;margin-right:8px;background:${tint[k]};"></span>${k}:${v}`;
        legend.appendChild(lg);
      }
      if (!segs.length){
        segs.push("rgba(255,255,255,.10) 0% 100%");
        legend.innerHTML = `<div class="lg" style="opacity:.7;">No counts</div>`;
      }
      donut.style.background = `conic-gradient(${segs.join(",")})`;
      const card = donut.closest(".vsp_card");
      if (card){
        const t = card.querySelector("div[style*='opacity']");
        if (t) t.textContent = total ? `Total findings: ${total}` : `No counts`;
      }
    }

    function updateKpi(counts){
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
        rows.innerHTML = `<tr><td colspan="4" style="opacity:.7;">No findings array (expected items[]).</td></tr>`;
        return;
      }

      const top = findings.slice().sort((a,b)=>{
        const sa = W[normSev(a?.severity)] ?? 9;
        const sb = W[normSev(b?.severity)] ?? 9;
        if (sa!==sb) return sa-sb;
        return String(a?.tool||"").localeCompare(String(b?.tool||""));
      }).slice(0, 12);

      rows.innerHTML = top.map(f=>{
        const sev = normSev(f?.severity);
        const tool = (f?.tool||"—").toString();
        const title = (f?.title||f?.name||f?.message||"—").toString();
        const rule = (f?.rule_id||f?.id||"").toString();
        const loc  = (f?.location||f?.path||f?.file||"—").toString();
        const t = rule ? `${title} • ${rule}` : title;
        return `<tr>
          <td>${sevBadge(sev)}</td>
          <td style="opacity:.9;">${esc(tool)}</td>
          <td style="opacity:.92;">${esc(t).slice(0,220)}</td>
          <td style="opacity:.85;font-family:ui-monospace,monospace;font-size:11.5px;">${esc(loc).slice(0,220)}</td>
        </tr>`;
      }).join("");
    }

    function ensureIframeFetch(){
      return new Promise((resolve)=>{
        let fr = document.getElementById("vsp_native_fetch_iframe_v4");
        if (fr && fr.contentWindow && fr.contentWindow.fetch) return resolve(fr.contentWindow.fetch.bind(fr.contentWindow));
        fr = document.createElement("iframe");
        fr.id = "vsp_native_fetch_iframe_v4";
        fr.style.cssText = "position:fixed;left:-9999px;top:-9999px;width:1px;height:1px;opacity:0;pointer-events:none;";
        fr.src = "about:blank";
        fr.onload = ()=> {
          try{
            if (fr.contentWindow && fr.contentWindow.fetch) resolve(fr.contentWindow.fetch.bind(fr.contentWindow));
            else resolve(window.fetch.bind(window));
          }catch(_){
            resolve(window.fetch.bind(window));
          }
        };
        document.body.appendChild(fr);
      });
    }

    async function runOnce(){
      const nfetch = await ensureIframeFetch();

      // meta RID
      const meta = await (await nfetch("/api/vsp/runs?_ts="+Date.now(), {cache:"no-store"})).json();
      const rid = meta?.rid_latest_gate_root || meta?.rid_latest || meta?.rid_last_good || meta?.rid_latest_findings || "";
      if (!rid) return;

      // IMPORTANT: bypass wrapper by using iframe native fetch
      const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&vsp_no_rewrite=1&_ts=${Date.now()}`;
      const root = await (await nfetch(url, {cache:"no-store"})).json();

      const counts = countsFromMeta(root?.meta?.counts_by_severity);
      const items = (Array.isArray(root?.items) ? root.items : (Array.isArray(root?.findings) ? root.findings : []));
      updateKpi(counts);
      renderDonut(counts);
      renderTop(items, rid);

      console.log("[VSP][BypassV4] ok rid=", rid, "items=", items.length, "counts=", counts);
    }

    // burst apply to override any late render
    let k=0;
    const t = setInterval(()=>{
      k++;
      runOnce().catch(e=>console.warn("[VSP][BypassV4] err", e));
      if (k>=6) clearInterval(t);
    }, 900);

    setInterval(()=> {
      if (document.visibilityState && document.visibilityState !== "visible") return;
      runOnce().catch(()=>{});
    }, 120000);

    console.log("[VSP][BypassV4] installed");
  }catch(e){
    console.warn("[VSP][BypassV4] init failed", e);
  }
})();
"""
p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended bypass rewrite v4")
PY

node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] HARD reload /vsp5 (Ctrl+Shift+R). Expect console: [VSP][BypassV4] installed + counts non-zero."
