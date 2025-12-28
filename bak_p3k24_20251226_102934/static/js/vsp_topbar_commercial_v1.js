
// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = function(){ return document.visibilityState === "visible"; };
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.backoff = async function(fn, opt){
      opt = opt || {};
      let delay = opt.delay || 800;
      const maxDelay = opt.maxDelay || 8000;
      const maxTries = opt.maxTries || 6;
      for(let i=0;i<maxTries;i++){
        if(!window.__VSP_CIO.visible()){
          await window.__VSP_CIO.sleep(600);
          continue;
        }
        try { return await fn(); }
        catch(e){
          if(window.__VSP_CIO.debug) console.warn("[VSP] backoff retry", i+1, e);
          await window.__VSP_CIO.sleep(delay);
          delay = Math.min(maxDelay, delay*2);
        }
      }
      throw new Error("backoff_exhausted");
    };
    window.__VSP_CIO.api = {
      ridLatest: ()=>"/api/vsp/rid_latest_v3",
      runs: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gate: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsPage: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifact: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();

/* VSP_P2_JS_ASSET_V_PINNED_V1 */
(function(){
  try {
    if (!window.__VSP_ASSET_V) window.__VSP_ASSET_V = "20251224_122204";
  } catch(e) {}
})();
function __vspAssetV(){
  try {
    return (window.__VSP_ASSET_V || "20251224_122204");
  } catch(e) {
    return "20251224_122204";
  }
}

/* VSP_P0_SINGLEFLIGHT_TOPBAR_V1N7 */
/* VSP_TOPBAR_COMMERCIAL_V1 */
(() => {
  if (window.__vsp_topbar_commercial_v1) return;
if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp_topbar_commercial_v1 = true; }
  const $ = (sel, root=document) => root.querySelector(sel);

  function envLabel(){
    const h = String(window.location.hostname || "");
    if (h.includes("staging")) return "STAGING";
    if (h.includes("localhost") || h.includes("127.0.0.1")) return "LOCAL";
    return "PROD";
  }

  function setText(id, v){
    const el = document.getElementById(id);
    if (el) el.textContent = (v == null ? "" : String(v));
  }

  function setPill(id, text, klass){
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = text;
    el.classList.remove("ok","warn","bad","muted");
    if (klass) el.classList.add(klass);
  }

  async function getJson(url, timeoutMs=6000){
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: c.signal, credentials: "same-origin"});
      if (!r.ok) throw new Error("HTTP " + r.status);
      return await r.json();
    } finally {
      clearTimeout(t);
    }
  }

  function wireExport(rid){
    const aCsv = $("#vspExportCsv");
    const aTgz = $("#vspExportTgz");
    if (aCsv) aCsv.href = `/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
    if (aTgz) aTgz.href = `/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
  }

  function detectDegraded(summary){
    // Robust heuristics across versions
    if (!summary || typeof summary !== "object") return false;

    if (summary.degraded === true) return true;
    if (summary.degraded_tools && Number(summary.degraded_tools) > 0) return true;
    if (summary.degraded_count && Number(summary.degraded_count) > 0) return true;

    const tools = summary.tools || summary.by_tool || null;
    if (Array.isArray(tools)) {
      return tools.some(t => (t && (t.degraded === true || String(t.status||"").toUpperCase()==="DEGRADED")));
    }
    if (tools && typeof tools === "object") {
      return Object.values(tools).some(t => t && (t.degraded === true || String(t.status||"").toUpperCase()==="DEGRADED"));
    }
    return false;
  }

  function detectVerdict(summary){
    const cand = [
      summary.overall,
      summary.overall_status,
      summary.verdict,
      summary.gate,
      summary.gate_verdict,
    ].filter(Boolean)[0];
    return cand ? String(cand).toUpperCase() : "UNKNOWN";
  }

  function verdictClass(v){
    const x = String(v||"").toUpperCase();
    if (x.includes("GREEN") || x==="OK" || x==="PASS") return "ok";
    if (x.includes("AMBER") || x==="WARN") return "warn";
    if (x.includes("RED") || x==="FAIL" || x==="BLOCK") return "bad";
    return "muted";
  }

  async function main(){
    setText("vspEnv", envLabel());
    setText("vspLatestRid", "…");
    setPill("vspVerdictPill", "…", "muted");
    setPill("vspDegradedPill", "…", "muted");

    // Latest RID
    let rid = null;
    try{
      const runs = await getJson("/api/vsp/rid_latest_v3", 7000);
      rid = (runs && runs.items && runs.items[0] && runs.items[0].run_id) ? runs.items[0].run_id : null;
    } catch(_) {}

    if (!rid){
      setText("vspLatestRid", "—"); try{ var el=document.getElementById("vspLatestRid"); if(el){ el.title="Select a valid RID"; el.style.cursor="pointer"; el.onclick=function(){ try{ window.__vsp_openRidPicker?.(); }catch(e){} }; } }catch(e){}
      wireExport("—");
      setPill("vspVerdictPill", "UNKNOWN", "muted");
      setPill("vspDegradedPill", "UNKNOWN", "muted");
      return;
    }

    setText("vspLatestRid", rid);
    wireExport(rid);

    // Summary for verdict/degraded
    try{
      // Prefer run_file if gateway serves it
      const summary = await getJson(`/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/")}`, 8000);
      const verdict = detectVerdict(summary);
      const degraded = detectDegraded(summary);

      setPill("vspVerdictPill", verdict, verdictClass(verdict));
      setPill("vspDegradedPill", degraded ? "DEGRADED" : "OK", degraded ? "warn" : "ok");
    } catch(_) {
      setPill("vspVerdictPill", "UNKNOWN", "muted");
      setPill("vspDegradedPill", "UNKNOWN", "muted");
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", main);
  } else {
    main();
  }
})();


