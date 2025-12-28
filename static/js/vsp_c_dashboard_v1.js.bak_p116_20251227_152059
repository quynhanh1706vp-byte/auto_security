(function(){
  const U = window.__VSPC;
  const rid = U.rid();
  const tb = document.getElementById("tb");

  function row(it){
    const sev=(it.severity||"INFO").toUpperCase();
    return `<tr>
      <td><span class="sev"><span class="s-dot ${U.sevDot(sev)}"></span>${U.esc(sev)}</span></td>
      <td>${U.esc(it.title||"(no title)")}</td>
      <td>${U.esc(it.tool||it.scanner||"")}</td>
      <td class="muted">${U.esc(U.shortFile(it.file||""))}</td>
    </tr>`;
  }

  async function load(){
    document.getElementById("k-time").textContent = new Date().toLocaleString();

    const f = await U.jget(`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=1&offset=0&pin=${encodeURIComponent(U.mode())}`);
    if (f && f.ok){
      document.getElementById("k-total").textContent = (f.total_findings != null ? String(f.total_findings) : "—");
      document.getElementById("k-from").textContent = "from_path: " + (f.from_path||"—");
      U.paintPills(f);
    } else {
      document.getElementById("k-total").textContent = "ERR";
      document.getElementById("k-from").textContent = "from_path: (api err)";
    }

    const t = await U.jget(`/api/vsp/top_findings_v3c?rid=${encodeURIComponent(rid)}&limit=200&pin=${encodeURIComponent(U.mode())}`);
    const items = (t && t.items) ? t.items : [];
    document.getElementById("k-toplen").textContent = String(items.length);
    document.getElementById("t-meta").textContent = `items=${items.length}  limit=${t.limit_applied||200}`;
    tb.innerHTML = items.length ? items.slice(0,200).map(row).join("") : `<tr><td colspan="4" class="muted">No items</td></tr>`;

    const tr = await U.jget(`/api/vsp/trend_v1`);
    const pts = (tr && (tr.points||tr.data)) || [];
    document.getElementById("k-trend").textContent = String(Array.isArray(pts)?pts.length:0);
    document.getElementById("trend-mini").textContent =
      Array.isArray(pts) && pts.length ? `latest: ${(pts[0].label||pts[0].ts||"").toString()}` : "no points";
  }

  document.addEventListener("DOMContentLoaded", load, {once:true});
  U.onRefresh(load);
})();
