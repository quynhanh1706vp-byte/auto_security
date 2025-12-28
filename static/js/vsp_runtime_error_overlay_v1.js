// VSP_P90_DOMREADY_BOOTFIX_V1
function __vsp_onReady(fn){
  try{
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn, { once:true });
    } else {
      fn();
    }
  } catch(e){
    console.error("[VSP_P90] onReady wrapper failed:", e);
  }
}

/* P64_RUNTIME_OVERLAY_V1 */
(() => {
  const $ = (sel) => document.querySelector(sel);

  function makePanel() {
    const el = document.createElement("div");
    el.id = "vsp-runtime-overlay";
    el.style.cssText = [
      "position:fixed",
      "right:12px",
      "bottom:12px",
      "z-index:2147483647",
      "width:420px",
      "max-height:48vh",
      "overflow:auto",
      "font:12px/1.35 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace",
      "background:rgba(0,0,0,.80)",
      "border:1px solid rgba(255,255,255,.12)",
      "border-radius:12px",
      "padding:10px",
      "color:#e5e7eb",
      "box-shadow:0 10px 30px rgba(0,0,0,.35)"
    ].join(";");
    el.innerHTML = `
      <div style="display:flex;gap:8px;align-items:center;justify-content:space-between;margin-bottom:8px">
        <div id="vsp_overlay_p64_root" data-vsp-overlay="p64"><b>VSP Runtime Overlay</b> <span style="opacity:.7">(P64)</span></div>
        <div style="display:flex;gap:6px">
          <button id="vsp-ovl-clear" style="cursor:pointer;border:1px solid rgba(255,255,255,.15);background:rgba(255,255,255,.06);color:#e5e7eb;border-radius:8px;padding:4px 8px">Clear</button>
          <button id="vsp-ovl-hide" style="cursor:pointer;border:1px solid rgba(255,255,255,.15);background:rgba(255,255,255,.06);color:#e5e7eb;border-radius:8px;padding:4px 8px">Hide</button>
        </div>
      </div>
      <div id="vsp-ovl-meta" style="white-space:pre-wrap;opacity:.85;margin-bottom:8px"></div>
      <div id="vsp-ovl-log" style="white-space:pre-wrap"></div>
    `;
    document.documentElement.appendChild(el);
    $("#vsp-ovl-clear").onclick = () => { $("#vsp-ovl-log").textContent = ""; };
    $("#vsp-ovl-hide").onclick = () => { el.style.display = "none"; };
    return el;
  }

  const panel = makePanel();
  const logEl = $("#vsp-ovl-log");
  const metaEl = $("#vsp-ovl-meta");

  function now() {
    const d = new Date();
    return d.toISOString().slice(11, 19);
  }
  function log(line) {
    logEl.textContent += `[${now()}] ${line}\n`;
    logEl.scrollTop = logEl.scrollHeight;
  }

  // Basic meta / mounts
  function mountStats() {
    const a = document.getElementById("vsp5_root");
    const b = document.getElementById("vsp-dashboard-main");
    const rid = new URL(location.href).searchParams.get("rid") || "";
    metaEl.textContent =
      `url=${location.pathname}${location.search}\n` +
      `rid=${rid || "(empty)"}\n` +
      `#vsp5_root children=${a ? a.children.length : "(missing)"}\n` +
      `#vsp-dashboard-main children=${b ? b.children.length : "(missing)"}\n`;
  }
  mountStats();
  setInterval(mountStats, 1000);

  // capture errors
  window.addEventListener("error", (e) => {
    log(`ERROR: ${e.message} @ ${e.filename}:${e.lineno}:${e.colno}`);
  });
  window.addEventListener("unhandledrejection", (e) => {
    const msg = (e && e.reason && (e.reason.stack || e.reason.message)) ? (e.reason.stack || e.reason.message) : String(e.reason);
    log(`UNHANDLED: ${msg}`);
  });

  // patch fetch for visibility
  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if (_fetch) {
    window.fetch = async (...args) => {
      const url = String(args[0] || "");
      try {
        const res = await _fetch(...args);
        if (!res.ok) log(`FETCH ${res.status} ${url}`);
        return res;
      } catch (err) {
        log(`FETCH_FAIL ${url} :: ${(err && err.message) ? err.message : String(err)}`);
        throw err;
      }
    };
  }

  // proactive probes (same-origin)
  async function probe() {
    try {
      const res = await fetch("/api/vsp/top_findings_v2?limit=1", { cache: "no-store" });
      const j = await res.json().catch(() => null);
      log(`probe top_findings_v2 status=${res.status} rid=${j && (j.rid || j.run_id) ? (j.rid || j.run_id) : "(no rid)"}`);
    } catch (e) {
      log(`probe top_findings_v2 FAIL ${(e && e.message) ? e.message : String(e)}`);
    }
  }
  setTimeout(probe, 500);

  log("overlay loaded");
})();


/* VSP_P77_P64_DEBUG_ONLY_V1 */
(function(){
  try{
    var debug = false;
    try{ debug = /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }catch(e){}
    if (!debug){
      var el = document.getElementById("vsp_overlay_p64_root");
      if (el) el.style.display = "none";
    }
  }catch(e){}
})();


/* VSP_P77B_P64_FORCE_HIDE_V1
 * Default: hide overlay unless ?debug=1 OR localStorage.vsp_p64_show=1
 * Persist hide/show.
 */
(function(){
  function hasDebug(){
    try{ return /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }catch(e){ return false; }
  }
  function wantShow(){
    try{ return (localStorage.getItem("vsp_p64_show") === "1"); }catch(e){ return false; }
  }
  function setShow(v){
    try{ localStorage.setItem("vsp_p64_show", v ? "1" : "0"); }catch(e){}
  }

  function findOverlayRoot(){
    // Find any node containing the exact label
    var nodes = document.querySelectorAll("div,span,b,strong");
    for (var i=0;i<nodes.length;i++){
      var t = (nodes[i].textContent||"").trim();
      if (t.indexOf("VSP Runtime Overlay") >= 0 && t.indexOf("(P64)") >= 0){
        // climb up to a reasonable root (floating panel)
        var el = nodes[i];
        for (var k=0;k<8 && el; k++){
          if (el.style && (el.style.position === "fixed" || el.style.position === "absolute")) return el;
          el = el.parentElement;
        }
        // fallback: nearest div container
        el = nodes[i].closest("div");
        if (el) return el;
      }
    }
    return null;
  }

  function apply(){
    var debug = hasDebug();
    var show = debug || wantShow();
    var root = findOverlayRoot();
    if (!root) return;

    // mark
    root.setAttribute("data-vsp-overlay","p64");

    // Persist behavior: if not show => hide
    if (!show){
      root.style.display = "none";
    } else {
      root.style.display = "";
    }

    // Patch built-in Hide/Clear buttons to persist show/hide
    try{
      var btns = root.querySelectorAll("button");
      for (var i=0;i<btns.length;i++){
        var b = btns[i];
        var txt = (b.textContent||"").trim().toLowerCase();
        if (txt === "hide"){
          if (!b.getAttribute("data-p77b")){
            b.setAttribute("data-p77b","1");
            b.addEventListener("click", function(){
              setShow(false);
              try{ root.style.display="none"; }catch(e){}
            }, true);
          }
        }
        if (txt === "clear"){
          // no-op persist
        }
      }
    }catch(e){}
  }

  // Run multiple times to catch late DOM injection
  function loop(n){
    apply();
    if (n<=0) return;
    setTimeout(function(){ loop(n-1); }, 200);
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function(){ loop(25); }, {once:true});
  } else {
    loop(25);
  }
})();

