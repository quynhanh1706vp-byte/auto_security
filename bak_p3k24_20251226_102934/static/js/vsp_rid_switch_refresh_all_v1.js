
/* ===================== VSP_P0_STATELESS_RID_NOHOTCALLS_V1N6 =====================
   - If rid present in URL or localStorage: never call rid_latest / rid_latest_gate_root
   - Provide shared helpers for rid resolution (stateless-first)
=============================================================================== */
(function(){
  try{
    if (window.__VSP_RID_GUARD_V1N6__) return;
    window.__VSP_RID_GUARD_V1N6__ = true;

    window.__vspGetRidFromUrl = function(){
      try{ return (new URL(location.href)).searchParams.get("rid") || ""; }catch(e){ return ""; }
    };
    window.__vspGetRidFromLS = function(){
      try{ return localStorage.getItem("vsp_rid") || localStorage.getItem("VSP_RID") || ""; }catch(e){ return ""; }
    };
    window.__vspHasUserRid = function(){
      const u = window.__vspGetRidFromUrl();
      const l = window.__vspGetRidFromLS();
      return !!(u || l);
    };
    window.__vspResolveRidFast = function(){
      const u = window.__vspGetRidFromUrl();
      if (u) return u;
      const l = window.__vspGetRidFromLS();
      if (l) return l;
      return "";
    };
    window.__vspBlockHotRidEndpoints = function(url){
      try{
        const u = new URL(String(url), location.origin);
        if (u.origin !== location.origin) return false;
        const p = u.pathname || "";
        if ((p === "/api/vsp/rid_latest" || p === "/api/vsp/rid_latest_gate_root") && window.__vspHasUserRid()){
          return true;
        }
      }catch(e){}
      return false;
    };
  }catch(e){}
})();
 /* ===================== /VSP_P0_STATELESS_RID_NOHOTCALLS_V1N6 ===================== */

/* VSP_P0_RID_SWITCH_REFRESH_ALL_PANELS_V1 */
(function(){
  'use strict';

  const LS_KEY = 'vsp_rid_last';

  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function detectRidSelect(){
    const ids = ['#rid', '#RID', '#vsp-rid', '#vsp-rid-select', '#ridSelect', '#runRid', '#run-rid'];
    for (const id of ids){
      const el = document.querySelector(id);
      if (el && el.tagName === 'SELECT') return el;
    }
    const sels = $all('select');
    for (const s of sels){
      const opts = Array.from(s.options||[]);
      if (opts.some(o => (o.value||'').startsWith('VSP_') || (o.text||'').startsWith('VSP_'))) return s;
    }
    return null;
  }

  function getRid(){
    try{
      const u = new URL(location.href);
      return u.searchParams.get('rid') || '';
    }catch(_e){}
    const sel = detectRidSelect();
    return sel ? (sel.value || '') : '';
  }

  function setRidInUrl(rid){
    try{
      const u = new URL(location.href);
      u.searchParams.set('rid', rid);
      history.replaceState({}, '', u.toString());
    }catch(_e){}
  }

  async function fetchDashKpis(rid){
    const r = await fetch(`/api/vsp/dash_kpis?rid=${encodeURIComponent(rid)}`, {cache:'no-store'});
    if (!r.ok) throw new Error(`dash_kpis HTTP ${r.status}`);
    return await r.json();
  }

  function tryCall(fn, rid){
    try{
      if (typeof fn === 'function'){
        if (fn.length >= 1) fn(rid);
        else fn();
        return true;
      }
    }catch(_e){}
    return false;
  }

  function tryKnownHooks(rid){
    let hit = false;
    hit = tryCall(window.__vspDashboardReloadRid, rid) || hit;
    hit = tryCall(window.__vspReloadAllPanels, rid) || hit;
    hit = tryCall(window.vspReloadAllPanels, rid) || hit;
    hit = tryCall(window.reloadDashboard, rid) || hit;
    hit = tryCall(window.refreshDashboard, rid) || hit;
    hit = tryCall(window.loadDashboard, rid) || hit;
    return hit;
  }

  function broadcastRidChanged(rid){
    try{
      window.dispatchEvent(new CustomEvent('vsp:ridChanged', {detail:{rid}}));
      document.dispatchEvent(new CustomEvent('vsp:ridChanged', {detail:{rid}}));
    }catch(_e){}
  }

  async function fallbackSoftReloadIfStale(rid){
    // If panels refuse to refresh (unknown code paths), do a soft reload to /vsp5?rid=...
    // This is still "no F5" from user POV (automatic), and guarantees consistency.
    try{
      const k = await fetchDashKpis(rid);
      const expected = Number(k && k.total_findings || 0);

      // naive read of KPI total from DOM (best-effort)
      const txt = (document.body && document.body.innerText) ? document.body.innerText : '';
      const hasExpected = expected > 0 && txt.includes(String(expected));

      // If after hook attempts we still don't even see expected total anywhere, reload.
      if (!hasExpected){
        const u = new URL(location.href);
        u.pathname = '/vsp5';
        u.searchParams.set('rid', rid);
        u.searchParams.set('soft', '1');
        location.replace(u.toString());
      }
    }catch(_e){
      // if dash_kpis fails, do nothing
    }
  }

  async function onRidChange(rid){
    if (!rid) return;

    // persist + URL
    try{ localStorage.setItem(LS_KEY, rid); }catch(_e){}
    setRidInUrl(rid);

    // notify others + attempt refresh hooks
    broadcastRidChanged(rid);

    const hit = tryKnownHooks(rid);

    // Always refresh our injected “Commercial severity” panel (it already listens to select change,
    // but this ensures it refreshes even if select binding differs)
    try{
      if (typeof window.__VSP_COUNTS_TOTAL_FROM_DASH_KPIS !== 'undefined'){
        // nothing to do; panel handles itself
      }
    }catch(_e){}

    // Fallback: if no known hook existed, soft reload after short delay (only if stale)
    if (!hit){
      setTimeout(()=>fallbackSoftReloadIfStale(rid), 1200);
    }
  }

  function boot(){
    const sel = detectRidSelect();
    if (!sel) return;

    if (!sel.__vspAllPanelsBound){
      sel.__vspAllPanelsBound = true;
      sel.addEventListener('change', ()=>{
        const rid = sel.value || getRid();
        onRidChange(rid);
      }, {passive:true});
    }

    // initial: persist url rid if any
    const rid0 = getRid();
    if (rid0){
      try{ localStorage.setItem(LS_KEY, rid0); }catch(_e){}
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();


// VSP_P0_STATELESS_RID_NOHOTCALLS_V1N6 helper
async function __vspFetchJsonGuardV1N6(url){
  if (window.__vspBlockHotRidEndpoints && window.__vspBlockHotRidEndpoints(url)){
    // Return a synthetic response consistent enough for callers to proceed.
    // Prefer rid from URL/LS.
    const rid = (window.__vspResolveRidFast && window.__vspResolveRidFast()) || "";
    return { ok:true, rid: rid, blocked:true };
  }
  const r = await fetch(url, { credentials: "same-origin" });
  if (!r.ok) throw new Error("HTTP "+r.status+" for "+url);
  return await r.json();
}
