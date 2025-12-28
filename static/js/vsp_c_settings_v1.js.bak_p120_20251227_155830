(function(){
  const U = window.__VSPC;
  const tb = document.getElementById("s-tb");
  const sp = document.getElementById("s-pin");

  function set(m){ localStorage.setItem("vsp_pin_mode_v2", m); sp.textContent = m.toUpperCase(); }
  document.getElementById("s-set-auto").addEventListener("click", ()=>set("auto"), {passive:true});
  document.getElementById("s-set-global").addEventListener("click", ()=>set("global"), {passive:true});
  document.getElementById("s-set-rid").addEventListener("click", ()=>set("rid"), {passive:true});

  async function probe(name, url){
    try{
      const r = await fetch(url, {cache:"no-store", credentials:"same-origin"});
      return {name, ok:r.ok, code:r.status};
    }catch(e){
      return {name, ok:false, code:"ERR"};
    }
  }

  async function load(){
    sp.textContent = U.mode().toUpperCase();
    const rid = U.rid();
    const pin = U.mode();
    const list = await Promise.all([
      probe("findings_page_v3", `/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=1&offset=0&pin=${encodeURIComponent(pin)}`),
      probe("top_findings_v3c", `/api/vsp/top_findings_v3c?rid=${encodeURIComponent(rid)}&limit=10&pin=${encodeURIComponent(pin)}`),
      probe("trend_v1", `/api/vsp/trend_v1`),
      probe("runs", `/api/vsp/runs?limit=1&offset=0`)
    ]);
    tb.innerHTML = list.map(x => `<tr><td class="mono">${U.esc(x.name)}</td><td class="mono ${x.ok?'':'muted'}">${U.esc(String(x.code))}</td></tr>`).join("");
    document.getElementById("s-meta").textContent = "pin=" + pin.toUpperCase();
  }

  document.addEventListener("DOMContentLoaded", load, {once:true});
  U.onRefresh(load);
})();
