(function(){
  const U = window.__VSPC;
  const tb = document.getElementById("runs-tb");
  const q = document.getElementById("runs-q");

  let rows = [];

  function render(){
    const s = (q.value||"").toLowerCase().trim();
    const show = s ? rows.filter(r => (r._search||"").includes(s)) : rows;
    tb.innerHTML = show.length ? show.map(r=>r._html).join("") : `<tr><td colspan="3" class="muted">No rows</td></tr>`;
    document.getElementById("runs-meta").textContent = `rows=${show.length}/${rows.length}`;
  }

  async function load(){
    const j = await U.jget(`/api/vsp/runs?limit=80&offset=0`);
    const runs = (j && j.runs) ? j.runs : [];
    rows = runs.map(r=>{
      const rid = r.rid || r.run_id || r.id || "";
      const label = r.label || r.ts || r.time || "";
      const dash = `/c/dashboard?rid=${encodeURIComponent(rid)}`;
      const ds   = `/c/data_source?rid=${encodeURIComponent(rid)}`;
      const h = `<tr>
        <td class="mono">${U.esc(rid)}</td>
        <td class="mono muted">${U.esc(label)}</td>
        <td class="mono">
          <a class="tab" href="${dash}">Open Dashboard</a>
          <a class="tab" href="${ds}">Data Source</a>
        </td>
      </tr>`;
      return {_search:(rid+" "+label).toLowerCase(), _html:h};
    });
    render();
  }

  q.addEventListener("input", ()=>render(), {passive:true});
  document.addEventListener("DOMContentLoaded", load, {once:true});
  U.onRefresh(load);
})();
