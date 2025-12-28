console.log("[VSP_UI] vsp_tabs_runtime_fix.js loaded");

document.addEventListener("DOMContentLoaded", () => {
  // Nút tab ngang: Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides
  const buttons = document.querySelectorAll(".vsp-tab-btn");

  // 5 panel nội dung
  const panels = {
    dashboard:  document.getElementById("tab-dashboard"),
    runs:       document.getElementById("tab-runs"),
    datasource: document.getElementById("tab-datasource"),
    settings:   document.getElementById("tab-settings"),
    overrides:  document.getElementById("tab-overrides"),
  };

  console.log(
    "[VSP_UI][TABS_FIX] buttons=",
    buttons.length,
    "panels=",
    Object.values(panels).filter(Boolean).length
  );

  if (!buttons.length) {
    console.warn("[VSP_UI][TABS_FIX] Không thấy .vsp-tab-btn");
  }

  function showTab(name) {
    Object.entries(panels).forEach(([key, el]) => {
      if (!el) return;
      const active = key === name;
      el.style.display = active ? "" : "none";
      el.classList.toggle("active", active);
      el.classList.toggle("is-active", active);
    });

    buttons.forEach((btn) => {
      const tab = btn.dataset.tab;
      const active = tab === name;
      btn.classList.toggle("active", active);
      btn.classList.toggle("is-active", active);
    });

    console.log("[VSP_UI][TABS_FIX] showTab =", name);
  }

  buttons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const tab = btn.dataset.tab;
      if (!tab) return;
      showTab(tab);
    });
  });

  // Mặc định: Dashboard
  showTab("dashboard");
});
