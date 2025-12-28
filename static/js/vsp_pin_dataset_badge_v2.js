/* VSP_PIN_DATASET_BADGE_V2 (freeze-safe) */
(function(){
  if (window.__VSP_BADGEPIN_V2_LOADED) return;
  window.__VSP_BADGEPIN_V2_LOADED = true;

  const LS_KEY = "vsp_pin_mode_v2"; // auto|global|rid
  const MODES = ["auto","global","rid"];
  const safeGetMode = () => {
    const m = (localStorage.getItem(LS_KEY) || "auto").toLowerCase();
    return MODES.includes(m) ? m : "auto";
  };
  const setMode = (m) => {
    if (!MODES.includes(m)) m = "auto";
    localStorage.setItem(LS_KEY, m);
  };

  const qs = new URLSearchParams(location.search);
  const rid = qs.get("rid") || "";

  function el(tag, cls, text){
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function ensureHost(){
    let host = document.getElementById("vsp-topbar") || document.querySelector(".vsp-topbar") || document.body;
    const wrap = el("div", "vsp-badgepin-v2");
    wrap.style.cssText = [
      "position:fixed","top:10px","right:12px","z-index:99999",
      "display:flex","gap:8px","align-items:center",
      "background:rgba(12,14,18,.92)","border:1px solid rgba(255,255,255,.10)",
      "padding:8px 10px","border-radius:10px",
      "font:12px/1.2 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      "color:#e8e8e8",
      "box-shadow:0 10px 30px rgba(0,0,0,.35)"
    ].join(";");
    document.body.appendChild(wrap);
    return wrap;
  }

  function btn(label, mode){
    const b = el("button", "");
    b.textContent = label;
    b.type = "button";
    b.style.cssText = [
      "cursor:pointer","user-select:none",
      "border-radius:8px","padding:6px 8px",
      "border:1px solid rgba(255,255,255,.14)",
      "background:rgba(255,255,255,.06)","color:#fff"
    ].join(";");
    b.addEventListener("click", () => {
      setMode(mode);
      // keep rid, add pin param for transparency (backend may or may not honor)
      const u = new URL(location.href);
      u.searchParams.set("rid", rid);
      u.searchParams.set("pin", mode);
      location.href = u.toString();
    }, {passive:true});
    return b;
  }

  function pill(text){
    const p = el("span","");
    p.textContent = text;
    p.style.cssText = [
      "padding:6px 8px","border-radius:999px",
      "border:1px solid rgba(255,255,255,.12)",
      "background:rgba(0,0,0,.25)"
    ].join(";");
    return p;
  }

  async function fetchDataSource(){
    // call findings_page_v3 (small, limit=1) to know effective from_path -> data_source
    const mode = safeGetMode();
    const u = "/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid) + "&limit=1&offset=0&pin=" + encodeURIComponent(mode);
    try{
      const r = await fetch(u, {cache:"no-store", credentials:"same-origin"});
      const j = await r.json();
      return {
        ok: !!j.ok,
        data_source: j.data_source || "UNKNOWN",
        pin_mode: j.pin_mode || mode,
        from_path: j.from_path || ""
      };
    }catch(e){
      return { ok:false, data_source:"ERR", pin_mode:safeGetMode(), from_path:"" };
    }
  }

  function paint(wrap, info){
    wrap.innerHTML = "";
    const mode = safeGetMode();

    const ds = pill("DATA SOURCE: " + (info.data_source || "UNKNOWN"));
    const pm = pill("PIN: " + mode.toUpperCase());
    const rp = pill("RID: " + (rid ? rid : "(none)"));
wrap && wrap.appendChild(ds);
wrap && wrap.appendChild(pm);
wrap && wrap.appendChild(rp);
    const sep = el("span","", " ");
    sep.style.cssText="opacity:.6";
wrap && wrap.appendChild(sep);wrap && wrap.appendChild(btn("AUTO", "auto"));
wrap && wrap.appendChild(btn("PIN GLOBAL", "global"));
wrap && wrap.appendChild(btn("USE RID", "rid"));
  }

  function boot(){
    const wrap = ensureHost();
    // paint quickly first
    paint(wrap, {data_source:"…", pin_mode:safeGetMode(), from_path:""});
    // then async update
    setTimeout(async () => {
      const info = await fetchDataSource();
      paint(wrap, info);
    }, 50);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, {once:true});
  } else {
    boot();
  }
})();

/* VSP_P82_DOM_GUARD_V1 */
(function(){
  try{
    if(window.__VSP_P82_ERR_GUARD) return;
    window.__VSP_P82_ERR_GUARD = 1;
    window.addEventListener("error", function(ev){
      try{ console.warn("[VSP][P82] runtime error guarded:", ev && (ev.message||ev.error||ev)); }catch(e){}
    });
    window.addEventListener("unhandledrejection", function(ev){
      try{ console.warn("[VSP][P82] rejection guarded:", ev && (ev.reason||ev)); }catch(e){}
    });
  }catch(e){}
})();

