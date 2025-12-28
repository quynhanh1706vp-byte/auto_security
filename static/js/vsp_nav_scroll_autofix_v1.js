/* VSP_NAV_SCROLL_AUTOFIX_V1: make left nav scrollable even when CSS selector unknown */
(function(){
  function pickNavContainer(anchor){
    // Walk up and find an ancestor that contains multiple nav items (sidebar list)
    let p = anchor;
    for (let i=0; i<20 && p; i++){
      try {
        const items = p.querySelectorAll ? p.querySelectorAll(".vsp-nav-item, a.vsp-tab, a[data-tab]") : [];
        if (items && items.length >= 4) return p;
      } catch(_){}
      p = p.parentElement;
    }
    return null;
  }

  function apply(){
    const tab = document.getElementById("tab-rules");
    if (!tab) return;

    // Ensure it isn't accidentally hidden
    tab.style.display = "";
    tab.style.visibility = "visible";

    const nav = pickNavContainer(tab) || tab.parentElement;
    if (!nav) return;

    // Make scrollable
    nav.style.overflowY = "auto";
    nav.style.maxHeight = "100vh";
    nav.style.webkitOverflowScrolling = "touch";

    // If nav is inside a fixed sidebar, also allow its parent to not clip
    if (nav.parentElement){
      nav.parentElement.style.overflow = "visible";
    }
    console.log("[VSP_NAV_SCROLL_AUTOFIX_V1] applied");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", apply);
  } else {
    apply();
  }
  window.addEventListener("hashchange", apply);
})();
