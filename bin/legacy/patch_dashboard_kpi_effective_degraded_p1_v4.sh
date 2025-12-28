#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_kpi_eff_degr_${TS}" && echo "[BACKUP] $F.bak_kpi_eff_degr_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_DASH_KPI_EFFECTIVE_DEGRADED_P1_V4"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

addon = r'''
/* VSP_DASH_KPI_EFFECTIVE_DEGRADED_P1_V4: show effective/raw + overrides delta + degraded clickable logs */
(function(){
  'use strict';

  function normRid(x){
    if(!x) return "";
    return String(x).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,'');
  }
  function getRid(){
    try{
      return normRid(localStorage.getItem("vsp_rid_selected_v2") || localStorage.getItem("vsp_rid_selected") || "");
    }catch(e){ return ""; }
  }
  async function jget(url){
    const r = await fetch(url, {cache:"no-store"});
    const ct = (r.headers.get("content-type")||"");
    if(!r.ok) throw new Error("HTTP "+r.status+" "+url);
    if(ct.includes("application/json")) return await r.json();
    // tolerate non-json
    return {ok:false, _nonjson:true, text: await r.text()};
  }
  function ensureBar(){
    let bar = document.getElementById("vsp-dash-p1-badges");
    if(!bar){
      bar = document.createElement("div");
      bar.id="vsp-dash-p1-badges";
      bar.style.cssText="position:sticky;top:0;z-index:9999;margin:10px 0;padding:10px;border-radius:14px;border:1px solid rgba(148,163,184,.18);background:rgba(2,6,23,.45);backdrop-filter: blur(6px);display:flex;flex-wrap:wrap;gap:10px;align-items:center;";
      document.body.insertBefore(bar, document.body.firstChild);
    }
    return bar;
  }
  function pill(txt, tone){
    const map = {
      ok: "border:1px solid rgba(34,197,94,.35);",
      warn:"border:1px solid rgba(245,158,11,.35);",
      bad: "border:1px solid rgba(239,68,68,.35);",
      info:"border:1px solid rgba(148,163,184,.25);"
    };
    return `<span style="display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;background:rgba(2,6,23,.35);color:#e2e8f0;font-size:12px;${map[tone]||map.info}">${txt}</span>`;
  }
  function linkPill(label, url, tone){
    const map = {
      ok: "border:1px solid rgba(34,197,94,.35);",
      warn:"border:1px solid rgba(245,158,11,.35);",
      bad: "border:1px solid rgba(239,68,68,.35);",
      info:"border:1px solid rgba(148,163,184,.25);"
    };
    return `<a target="_blank" rel="noopener" href="${url}"
      style="display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;background:rgba(2,6,23,.35);color:#e2e8f0;font-size:12px;text-decoration:none;${map[tone]||map.info}">
      ${label}</a>`;
  }

  function pickLogRel(tool){
    const t = String(tool||"").toLowerCase();
    if(t.includes("kics")) return "kics/kics.log";
    if(t.includes("trivy")) return "trivy/trivy.json.err";
    if(t.includes("codeql")) return "codeql/codeql.log";
    if(t.includes("semgrep")) return "semgrep/semgrep.json";
    if(t.includes("gitleaks")) return "gitleaks/gitleaks.json";
    if(t.includes("bandit")) return "bandit/bandit.json";
    if(t.includes("syft")) return "syft/syft.json";
    if(t.includes("grype")) return "grype/grype.json";
    return "";
  }
  function artUrl(rid, rel){
    return "/api/vsp/run_artifact_raw_v1/" + encodeURIComponent(rid) + "?rel=" + encodeURIComponent(rel);
  }

  async function render(){
    const bar = ensureBar();
    const rid = getRid() || (await jget("/api/vsp/latest_rid_v1")).run_id;
    const ridN = normRid(rid||"");
    if(!ridN){
      bar.innerHTML = pill("RID: (none)", "warn") + pill("No RID selected", "warn");
      return;
    }

    let eff=null, st=null;
    try{
      eff = await jget("/api/vsp/findings_effective_v1/" + encodeURIComponent(ridN) + "?limit=0");
    }catch(e){
      eff = {ok:false, error:String(e)};
    }
    try{
      st = await jget("/api/vsp/run_status_v2/" + encodeURIComponent(ridN));
    }catch(e){
      st = {ok:false, error:String(e)};
    }

    const rawTotal = eff && typeof eff.raw_total==="number" ? eff.raw_total : null;
    const effTotal = eff && typeof eff.effective_total==="number" ? eff.effective_total : null;
    const d = (eff && eff.delta) ? eff.delta : {};
    const sup = (d && typeof d.suppressed_n==="number") ? d.suppressed_n : null;
    const chg = (d && typeof d.changed_severity_n==="number") ? d.changed_severity_n : null;
    const match = (d && typeof d.matched_n==="number") ? d.matched_n : null;
    const applied = (d && typeof d.applied_n==="number") ? d.applied_n : null;

    const degraded = (st && st.degraded_tools && Array.isArray(st.degraded_tools)) ? st.degraded_tools : [];
    const degrN = degraded.length;

    let html = "";
    html += pill("RID: "+ridN, "info");
    if(rawTotal!=null && effTotal!=null){
      const tone = (effTotal < rawTotal) ? "ok" : "info";
      html += pill(`Effective ${effTotal} / Raw ${rawTotal}`, tone);
    }else{
      html += pill("Effective/Raw: n/a", "warn");
    }

    if(match!=null) html += pill(`Overrides matched: ${match}`, "info");
    if(applied!=null) html += pill(`Overrides applied: ${applied}`, applied>0 ? "ok" : "info");
    if(sup!=null) html += pill(`Suppressed: ${sup}`, sup>0 ? "ok" : "info");
    if(chg!=null) html += pill(`Severity changed: ${chg}`, chg>0 ? "ok" : "info");

    // degraded clickable
    if(degrN>0){
      html += pill(`Degraded tools: ${degrN}`, "warn");
      degraded.slice(0,8).forEach(t=>{
        const rel = pickLogRel(t);
        if(rel) html += linkPill(`${t} log`, artUrl(ridN, rel), "warn");
        else html += pill(String(t), "warn");
      });
    }else{
      html += pill("Degraded: 0", "ok");
    }

    // quick links
    html += linkPill("CIO Report", "/vsp/report_cio_v1/"+encodeURIComponent(ridN), "info");
    html += linkPill("Unified.json", artUrl(ridN,"findings_unified.json"), "info");
    html += linkPill("Effective.json", artUrl(ridN,"findings_effective.json"), "info");

    bar.innerHTML = html;
  }

  // initial + refresh when RID changes (poll)
  let lastRid="";
  async function tick(){
    const rid=getRid();
    if(rid && rid!==lastRid){
      lastRid=rid;
      await render();
    }
  }

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>{ render(); setInterval(tick, 1200); });
  }else{
    render(); setInterval(tick, 1200);
  }
})();
'''
s = s.rstrip() + "\n\n" + MARK + "\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended dashboard KPI effective/degraded v4")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_kpi_effective_degraded_p1_v4"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
