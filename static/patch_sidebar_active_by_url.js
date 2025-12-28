document.addEventListener("DOMContentLoaded", () => {
  try {
    const path = window.location.pathname || "/";

    // Map URL -> label trên sidebar
    let targetLabel = "Dashboard";
    if (/^\/settings\b/.test(path)) {
      targetLabel = "Settings";
    } else if (/data[_-]source/i.test(path)) {
      targetLabel = "Data Source";
    } else if (/rules/i.test(path)) {
      targetLabel = "Rule overrides";
    } else if (/runs/i.test(path)) {
      targetLabel = "Runs & Reports";
    }

    const links = Array.from(
      document.querySelectorAll(".sb-sidebar a, .sb-nav a, nav a")
    );
    if (!links.length) return;

    const dashLink = links.find(el =>
      /Dashboard/i.test(el.textContent || "")
    );

    const targetLink = links.find(el => {
      const t = (el.textContent || "").trim();
      return new RegExp("^" + targetLabel + "$", "i").test(t);
    });

    if (!dashLink || !targetLink) return;

    const dashStyle = window.getComputedStyle(dashLink);

    // Nếu không đứng ở Dashboard thì tắt highlight của Dashboard
    if (dashLink !== targetLink) {
      dashLink.style.backgroundColor = "";
      dashLink.style.color = "";
      dashLink.style.boxShadow = "";
      dashLink.style.borderColor = "";
    }

    // Copy màu/box-shadow của Dashboard sang tab hiện tại
    targetLink.style.backgroundColor = dashStyle.backgroundColor;
    targetLink.style.color = dashStyle.color;
    targetLink.style.boxShadow = dashStyle.boxShadow;
    targetLink.style.borderColor = dashStyle.borderColor;
  } catch (e) {
    console.warn("[patch_sidebar_active_by_url] error:", e);
  }
});
