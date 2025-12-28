/* VSP_EXPORT_GUARD_V1 */
(function () {
  function hidePDF() {
    const sel = [
      'a[href*="fmt=pdf"]',
      'button[data-fmt="pdf"]',
      '[data-export-fmt="pdf"]',
      '[data-vsp-export="pdf"]'
    ].join(",");

    document.querySelectorAll(sel).forEach((n) => {
      n.style.display = "none";
      n.setAttribute("aria-hidden", "true");
    });

    // Heuristic: hide menu items with exact text "PDF"
    document.querySelectorAll("a,button,li,div,span").forEach((n) => {
      const t = (n.textContent || "").trim().toUpperCase();
      if (t === "PDF") {
        // hide container if it's obviously a menu item
        const box = n.closest("li") || n.closest("a") || n;
        box.style.display = "none";
      }
    });
  }

  function interceptPDFClicks() {
    document.addEventListener("click", (e) => {
      const a = e.target.closest && e.target.closest('a[href*="fmt=pdf"]');
      if (!a) return;
      e.preventDefault();
      e.stopPropagation();
      alert("PDF export is disabled in this commercial build. Use HTML or ZIP.");
    }, true);
  }

  window.addEventListener("DOMContentLoaded", () => {
    hidePDF();
    interceptPDFClicks();
    // re-hide after UI rerenders
    setTimeout(hidePDF, 800);
    setTimeout(hidePDF, 1800);
  });
})();
