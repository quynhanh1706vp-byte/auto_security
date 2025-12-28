/* VSP_RUNS_PAGE_MIN_P0_V1 */
(function(){
  const qs = (s, r=document)=>r.querySelector(s);
  const esc = (s)=>String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));
  async function fetchJSON(url, timeoutMs=6000){
    const ac = new AbortController();
    const t = setTimeout(()=>ac.abort(), timeoutMs);
    try{
      const r = await fetch(url, { cache:"no-store", signal: ac.signal, headers:{ "Accept":"application/json" } });
      const txt = await r.text();
      let j; try{ j = JSON.parse(txt); } catch(e){ throw new Error("bad json: " + txt.slice(0,140)); }
      return { httpOk: r.ok, status: r.status, json: j };
    } finally { clearTimeout(t); }
  }

  function render(items){
    const tbody = qs("#runs_tbody");
    const q = qs("#runs_q");
    const badge = qs("#runs_badge");
    if(!tbody) return;

    function apply(){
      const needle = (q?.value||"").trim().toLowerCase();
      tbody.innerHTML = "";
      let shown = 0;
      for(const it of items){
        const rid = it.run_id || "";
        if(needle && !rid.toLowerCase().includes(needle)) continue;
        shown++;
        const has = it.has || {};
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td class="rid">${esc(rid)}</td>
          <td>${has.summary ? "OK" : "-"}</td>
          <td>${has.json ? "OK" : "-"}</td>
          <td>${has.csv ? "OK" : "-"}</td>
          <td class="act">
            <a class="btn" href="/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=reports/" target="_blank">SUMMARY</a>
            <a class="btn" href="/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=reports/" target="_blank">JSON</a>
            <a class="btn" href="/api/vsp/export_csv?rid=${encodeURIComponent(rid)}" target="_blank">CSV</a>
          </td>`;
        tbody.appendChild(tr);
      }
      if(badge) badge.textContent = `runs: ${shown}/${items.length}`;
    }

    q && q.addEventListener("input", apply);
    apply();
  }

  async function main(){
    const st = qs("#runs_status");
    const badge = qs("#runs_badge");
    if(badge) badge.textContent = "runs: loading...";
    try{
      const r = await fetchJSON("/api/vsp/runs?limit=200", 8000);
      if(!r.httpOk) throw new Error("HTTP " + r.status);
      const j = r.json;
      if(!j || j.ok !== true || !Array.isArray(j.items)) throw new Error("bad contract: json.ok/items");
      if(st) st.textContent = `OK /api/vsp/runs (limit=${j.limit||200})`;
      render(j.items);
    }catch(e){
      console.error("[VSP][RUNS_MIN] failed:", e);
      if(st) st.textContent = "ERROR: " + (e?.message || String(e));
      if(badge) badge.textContent = "runs: error";
      const tbody = qs("#runs_tbody");
      if(tbody) tbody.innerHTML = `<tr><td colspan="5" class="muted">Runs API error: ${esc(e?.message||String(e))}</td></tr>`;
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
