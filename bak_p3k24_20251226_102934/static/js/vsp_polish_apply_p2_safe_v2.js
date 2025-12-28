/* VSP_P2_POLISH_SAFE_V2: scoped, capped, no layout-thrash */
(function(){
  if (window.__VSP_P2_POLISH_SAFE_V2__) return;
  window.__VSP_P2_POLISH_SAFE_V2__ = { ok:true, ts: Date.now() };

  function onReady(fn){
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, {once:true});
    else fn();
  }
  function add(el, cls){
    if (!el || !el.classList) return;
    cls.split(/\s+/).filter(Boolean).forEach(c => el.classList.add(c));
  }
  function q(root, sel){ try{ return root.querySelector(sel); }catch(_){ return null; } }
  function qa(root, sel){ try{ return Array.from(root.querySelectorAll(sel)); }catch(_){ return []; } }

  function apply(){
    try{
      // Only polish /vsp5 (dashboard). Others skip to avoid any risk.
      var p = (location && location.pathname) ? location.pathname : "";
      if (p !== "/vsp5") { window.__VSP_P2_POLISH_SAFE_V2__.skip = p; return; }

      var root = document.getElementById("vsp-dashboard-main") || document.body;
      if (!root) return;

      // KPI grid: prefer explicit ids/classes only
      var kpiGrid = q(root, "#vsp-kpi-grid") || q(root, ".vsp-kpi-grid") || q(root, "[data-kpi-grid]");
      if (kpiGrid) add(kpiGrid, "vsp-kpi-grid");

      // KPI cards: cap to avoid huge loops
      var kpiCards = qa(root, ".kpi-card, [data-kpi-card], .vsp-kpi-card");
      if (kpiCards.length > 80) kpiCards = kpiCards.slice(0, 80);
      kpiCards.forEach(function(card){
        add(card, "vsp-card vsp-kpi-card");
        var title = q(card, ".title, .kpi-title, h4, h5"); if (title) add(title, "vsp-kpi-title");
        var val   = q(card, ".value, .kpi-value, .num, .number, strong"); if (val) add(val, "vsp-kpi-value");
        var sub   = q(card, ".sub, .hint, .desc, small"); if (sub) add(sub, "vsp-kpi-sub");
      });

      // Panels: ONLY known dashboard sections (cap)
      var panels = qa(root, ".vsp-panel, [data-panel], .vsp-section");
      if (panels.length > 40) panels = panels.slice(0, 40);
      panels.forEach(function(el){ add(el, "vsp-panel"); });

      // Tables: cap
      var tables = qa(root, "table");
      if (tables.length > 12) tables = tables.slice(0, 12);
      tables.forEach(function(tbl){
        var host = tbl.closest(".vsp-table-tight") || tbl.parentElement;
        if (host) add(host, "vsp-table-tight");
      });

      window.__VSP_P2_POLISH_SAFE_V2__.applied = true;
    }catch(e){
      window.__VSP_P2_POLISH_SAFE_V2__.err = String(e && e.message ? e.message : e);
    }
  }

  // Defer to idle to avoid blocking first paint
  onReady(function(){
    if ("requestIdleCallback" in window) requestIdleCallback(apply, {timeout: 800});
    else setTimeout(apply, 120);
  });
})();
