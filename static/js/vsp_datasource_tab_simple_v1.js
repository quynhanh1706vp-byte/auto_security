(function () {
  console.log("[VSP_DS] vsp_datasource_tab_simple_v1.js loaded");

  const tbody = document.getElementById("vsp-ds-tbody");
  const inputSeverity = document.getElementById("vsp-ds-severity");
  const inputTool = document.getElementById("vsp-ds-tool");
  const inputCwe = document.getElementById("vsp-ds-cwe");
  const inputPath = document.getElementById("vsp-ds-path");
  const btnApply = document.getElementById("vsp-ds-apply");
  const btnReset = document.getElementById("vsp-ds-reset");

  let allFindings = [];

  async function loadData() {
    try {
      const resp = await fetch("/api/vsp/datasource_v2?limit=500");
      const data = await resp.json();
      if (!resp.ok || !data.items) {
        console.error("[VSP_DS] load error", data);
        return;
      }
      allFindings = data.items;
      render(allFindings);
    } catch (err) {
      console.error("[VSP_DS] loadData error", err);
    }
  }

  function render(items) {
    if (!tbody) return;
    tbody.innerHTML = "";
    items.forEach(f => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${f.run_id || ""}</td>
        <td>${f.tool || ""}</td>
        <td>${f.severity || ""}</td>
        <td>${f.cwe_id || ""}</td>
        <td>${f.file_path || ""}</td>
        <td>${f.rule_id || ""}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  function applyFilter() {
    const sev = (inputSeverity && inputSeverity.value || "").trim().toUpperCase();
    const tool = (inputTool && inputTool.value || "").trim().toLowerCase();
    const cwe = (inputCwe && inputCwe.value || "").trim().toUpperCase();
    const path = (inputPath && inputPath.value || "").trim().toLowerCase();

    const filtered = allFindings.filter(f => {
      if (sev && (f.severity || "").toUpperCase() !== sev) return false;
      if (tool && !(f.tool || "").toLowerCase().includes(tool)) return false;
      if (cwe && !(f.cwe_id || "").toUpperCase().includes(cwe)) return false;
      if (path && !(f.file_path || "").toLowerCase().includes(path)) return false;
      return true;
    });

    render(filtered);
  }

  function resetFilter() {
    if (inputSeverity) inputSeverity.value = "";
    if (inputTool) inputTool.value = "";
    if (inputCwe) inputCwe.value = "";
    if (inputPath) inputPath.value = "";
    render(allFindings);
  }

  if (btnApply) btnApply.addEventListener("click", applyFilter);
  if (btnReset) btnReset.addEventListener("click", resetFilter);

  document.addEventListener("DOMContentLoaded", loadData);
})();


// === VSP_DS_DRILLDOWN_SINK_V1 ===
(function(){
  const KEY = "vsp_ds_drill_url_v1";

  function hostEl(){
    return (
      document.querySelector("#tab-datasource") ||
      document.querySelector("#tab_datasource") ||
      document.querySelector("#datasource") ||
      document.querySelector("[data-tab='datasource']") ||
      document.body
    );
  }

  function ensurePre(){
    let pre = document.getElementById("vsp_ds_pre_v1");
    if(!pre){
      pre = document.createElement("pre");
      pre.id = "vsp_ds_pre_v1";
      pre.style.whiteSpace = "pre-wrap";
      pre.style.wordBreak = "break-word";
      pre.style.fontSize = "12px";
      pre.style.lineHeight = "1.35";
      pre.style.marginTop = "12px";
      pre.style.padding = "10px";
      pre.style.borderRadius = "12px";
      pre.style.border = "1px solid rgba(255,255,255,.10)";
      pre.style.background = "rgba(0,0,0,.25)";
      hostEl().appendChild(pre);
    }
    return pre;
  }

  async function refreshFromUrl(url){
    if(!url) return;
    const pre = ensurePre();
    pre.textContent = "Loading drilldown…\n" + url;

    try{
      const r = await fetch(url, {credentials:"same-origin"});
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      if(!ct.includes("application/json")){
        const tx = await r.text();
        pre.textContent = "Non-JSON response\n\n" + tx.slice(0, 4000);
        return;
      }
      const j = await r.json();
      pre.textContent = JSON.stringify(j, null, 2);
    } catch(e){
      pre.textContent = "ERR: " + String(e);
    }
  }

  // called by dashboard click
  window.VSP_DS_APPLY_DRILL_URL_V1 = function(url){
    try{ sessionStorage.setItem(KEY, url); } catch(e){}
    refreshFromUrl(url);
  };

  // auto-apply when entering datasource tab (or on load)
  window.addEventListener("load", ()=>{
    let url = null;
    try{ url = sessionStorage.getItem(KEY); } catch(e){}
    if(url){
      setTimeout(()=>refreshFromUrl(url), 400);
    }
  });
})();

