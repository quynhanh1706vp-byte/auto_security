window.VSP = (function () {
  const ERROR_TIMEOUT = 8000;
  const TOAST_TIMEOUT = 4000;
  let errorTimer = null;
  let toastTimer = null;

  function $(sel) {
    return document.querySelector(sel);
  }

  function $all(sel) {
    return Array.from(document.querySelectorAll(sel));
  }

  async function fetchJson(url) {
    const res = await fetch(url, { credentials: "same-origin" });
    if (!res.ok) {
      throw new Error(`[VSP] HTTP ${res.status} for ${url}`);
    }
    let data;
    try {
      data = await res.json();
    } catch (e) {
      throw new Error(`[VSP] Invalid JSON from ${url}`);
    }
    return data;
  }

  function showError(msg) {
    const el = $("#vsp-global-error");
    if (!el) return;
    el.textContent = msg || "Unexpected error.";
    el.style.display = "block";
    clearTimeout(errorTimer);
    errorTimer = setTimeout(() => {
      el.style.display = "none";
    }, ERROR_TIMEOUT);
  }

  function clearError() {
    const el = $("#vsp-global-error");
    if (!el) return;
    el.style.display = "none";
  }

  function showToast(msg) {
    const el = $("#vsp-global-toast");
    if (!el) return;
    el.textContent = msg || "";
    el.style.display = "block";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      el.style.display = "none";
    }, TOAST_TIMEOUT);
  }

  function severityClass(sev) {
    if (!sev) return "";
    const s = sev.toUpperCase();
    if (s === "CRITICAL") return "sev-critical";
    if (s === "HIGH") return "sev-high";
    if (s === "MEDIUM") return "sev-medium";
    if (s === "LOW") return "sev-low";
    if (s === "INFO") return "sev-info";
    if (s === "TRACE") return "sev-trace";
    return "";
  }

  function renderSeverityBadge(sev) {
    if (!sev) return "";
    const cls = severityClass(sev);
    return `<span class="vsp-sev-badge ${cls}">${sev.toUpperCase()}</span>`;
  }

  function activateTab(tabName) {
    const panes = $all(".vsp-tab-pane");
    panes.forEach(p => {
      if (p.id === `tab-${tabName}`) {
        p.classList.remove("vsp-tab-hidden");
      } else {
        p.classList.add("vsp-tab-hidden");
      }
    });

    const navItems = $all(".vsp-nav-item");
    navItems.forEach(btn => {
      const t = btn.getAttribute("data-tab");
      if (t === tabName) {
        btn.classList.add("vsp-nav-item-active");
      } else {
        btn.classList.remove("vsp-nav-item-active");
      }
    });

    const tabBtns = $all(".vsp-tab-btn");
    tabBtns.forEach(btn => {
      const t = btn.getAttribute("data-tab");
      if (t === tabName) {
        btn.classList.add("vsp-tab-btn-active");
      } else {
        btn.classList.remove("vsp-tab-btn-active");
      }
    });

    // Gọi init module tương ứng (idempotent)
    try {
      if (tabName === "dashboard" && window.VSP_DASHBOARD && window.VSP_DASHBOARD.init) {
        window.VSP_DASHBOARD.init();
      } else if (tabName === "runs" && window.VSP_RUNS && window.VSP_RUNS.init) {
        window.VSP_RUNS.init();
      } else if (tabName === "datasource" && window.VSP_DATASOURCE && window.VSP_DATASOURCE.init) {
        window.VSP_DATASOURCE.init();
      } else if (tabName === "settings" && window.VSP_SETTINGS && window.VSP_SETTINGS.init) {
        window.VSP_SETTINGS.init();
      } else if (tabName === "overrides" && window.VSP_OVERRIDES && window.VSP_OVERRIDES.init) {
        window.VSP_OVERRIDES.init();
      }
    } catch (e) {
      console.error("[VSP] init tab error", e);
      showError("Không tải được dữ liệu tab. Vui lòng kiểm tra backend.");
    }
  }

  function setupRouting() {
    // Sidebar
    $all(".vsp-nav-item[data-tab]").forEach(btn => {
      btn.addEventListener("click", () => {
        const tab = btn.getAttribute("data-tab");
        activateTab(tab);
      });
    });

    // Top tab buttons
    $all(".vsp-tab-btn[data-tab]").forEach(btn => {
      btn.addEventListener("click", () => {
        const tab = btn.getAttribute("data-tab");
        activateTab(tab);
      });
    });

    // Default tab
    activateTab("dashboard");
  }

  document.addEventListener("DOMContentLoaded", setupRouting);

  return {
    fetchJson,
    showError,
    clearError,
    showToast,
    renderSeverityBadge
  };
})();
