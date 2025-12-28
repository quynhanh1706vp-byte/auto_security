/* VSP_RUNS_PAGE_MIN_P0_V2 */
(function(){
  const $ = (sel, r=document)=>r.querySelector(sel);
  const esc = (s)=>String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));
  const API="/api/vsp/runs";

  let LAST=null;

  function setBanner(kind, msg){
    const b=$("#banner");
    if(!b) return;
    b.className = "banner " + (kind||"");
    b.textContent = msg || "";
    b.style.display = msg ? "block" : "none";
  }

  function render(items){
    const tbody=$("#runs_tbody");
    const loaded=$("#runs_loaded");
    if(loaded) loaded.textContent = String(items.length);
    if(!tbody) return;
    tbody.innerHTML="";
    for(const it of items){
      const rid = String(it?.run_id ?? "");
      const has = it?.has || {};
      const tr = document.createElement("tr");

      const tdRid = document.createElement("td");
      tdRid.innerHTML = `<code class="rid">${esc(rid)}</code>`;
      tr.appendChild(tdRid);

      const tdHas = document.createElement("td");
      const mk = (k)=> (has && has[k]) ? `<span class="ok">${k}:OK</span>` : `<span class="no">${k}:-</span>`;
      tdHas.innerHTML = `<div class="has">${mk("json")} ${mk("csv")} ${mk("sarif")} ${mk("summary")}</div>`;
      tr.appendChild(tdHas);

      const tdAct = document.createElement("td");
      const uSummary = `/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/")}`;
      const uCsv     = `/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
      const uTgz     = `/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
      const uSha     = `/api/vsp/sha256?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/")}`;
      tdAct.innerHTML = `
        <a class="btn" target="_blank" rel="noopener" href="${uSummary}">SUMMARY</a>
        <a class="btn" target="_blank" rel="noopener" href="${uCsv}">CSV</a>
        <a class="btn" target="_blank" rel="noopener" href="${uTgz}">TGZ</a>
        <a class="btn" target="_blank" rel="noopener" href="${uSha}">SHA</a>
      `;
      tr.appendChild(tdAct);

      tbody.appendChild(tr);
    }
  }

  function applyFilter(){
    if(!LAST){ return; }
    const q = ($("#q")?.value || "").trim().toLowerCase();
    let items = Array.isArray(LAST.items) ? LAST.items : [];
    if(q) items = items.filter(it=>String(it?.run_id||"").toLowerCase().includes(q));
    render(items);
    setBanner("", "");
  }

  async function reload(){
    setBanner("warn", "Loading runs…");
    const limit = parseInt(($("#limit")?.value || "200"), 10) || 200;
    const url = `${API}?limit=${encodeURIComponent(String(limit))}&_ts=${Date.now()}`;
    try{
      const resp = await fetch(url, {cache:"no-store", credentials:"same-origin"});
      const txt = await resp.text();
      let data;
      try{ data = JSON.parse(txt); } catch(e){ throw new Error("Bad JSON: " + txt.slice(0,160)); }
      if(!data || data.ok !== true || !Array.isArray(data.items)){
        throw new Error("Bad contract (expect {ok:true, items:[]})");
      }
      LAST = data;
      applyFilter();
      setBanner("", "");
    }catch(e){
      console.error("[RUNS_MIN] load failed:", e);
      setBanner("err", "RUNS API FAIL: " + (e?.message || String(e)));
    }
  }

  document.addEventListener("DOMContentLoaded", ()=>{
    $("#reload")?.addEventListener("click", ()=>reload());
    $("#q")?.addEventListener("input", ()=>applyFilter());
    $("#limit")?.addEventListener("change", ()=>reload());

    // show something immediately (never blank)
    setBanner("warn", "Booting /runs…");
    reload();
  });
})();
