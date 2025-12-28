/**
 * VSP_UI 2025 – Commercial polish layer (V2)
 * - KHÔNG thay đổi logic fetch hiện tại.
 * - Chỉ "enhance" DOM sau khi dữ liệu đã render:
 *   + Badge severity / tool ở Data Source (MutationObserver).
 *   + Row hover + selected ở Runs.
 *   + Toast khi Save Settings / Rules.
 */

(function () {
  const LOG_PREFIX = "[VSP_UI_COMMERCIAL]";

  function ready(fn) {
    if (document.readyState !== "loading") {
      fn();
    } else {
      document.addEventListener("DOMContentLoaded", fn);
    }
  }

  function getToastContainer() {
    let c = document.querySelector(".vsp-toast-container");
    if (!c) {
      c = document.createElement("div");
      c.className = "vsp-toast-container";
      document.body.appendChild(c);
    }
    return c;
  }

  function showToast(message, type) {
    type = type || "info";
    const c = getToastContainer();
    const toast = document.createElement("div");
    toast.className = "vsp-toast vsp-toast-" + type;
    toast.textContent = message;
    c.appendChild(toast);
    setTimeout(function () {
      toast.classList.add("vsp-toast-hide");
    }, 2200);
    setTimeout(function () {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, 2600);
  }

  /*  Runs & Reports  */
  function enhanceRunsTab() {
    const tbody = document.getElementById("vsp-runs-tbody");
    if (!tbody) {
      console.log(LOG_PREFIX, "Không thấy #vsp-runs-tbody – bỏ qua polish Runs.");
      return;
    }

    const table = tbody.closest("table");
    if (table && !table.classList.contains("vsp-table-hover")) {
      table.classList.add("vsp-table-hover");
    }

    tbody.addEventListener("click", function (ev) {
      const tr = ev.target.closest("tr");
      if (!tr || !tbody.contains(tr)) return;

      Array.from(tbody.querySelectorAll("tr")).forEach(function (row) {
        row.classList.remove("vsp-run-selected");
      });
      tr.classList.add("vsp-run-selected");

      const detailBox = document.getElementById("vsp-run-detail-box");
      if (!detailBox) return;

      const cells = tr.children;
      const runId =
        tr.getAttribute("data-run-id") ||
        (cells[0] && cells[0].textContent.trim()) ||
        "-";

      const startedAt =
        tr.getAttribute("data-started-at") ||
        (cells[1] && cells[1].textContent.trim()) ||
        "-";

      const profile =
        tr.getAttribute("data-profile") ||
        (cells[2] && cells[2].textContent.trim()) ||
        "-";

      const status =
        tr.getAttribute("data-status") ||
        (cells[3] && cells[3].textContent.trim()) ||
        "-";

      const mapField = function (field, value) {
        const el = detailBox.querySelector('[data-field="' + field + '"]');
        if (el) el.textContent = value || "-";
      };

      mapField("run_id", runId);
      mapField("started_at", startedAt);
      mapField("profile", profile);
      mapField("status", status);
    });
  }

  /*  Data Source  */

  function styleDataSourceRows(tbody) {
    const rows = Array.from(tbody.querySelectorAll("tr"));
    if (!rows.length) return;

    rows.forEach(function (tr) {
      const cells = tr.children;
      if (!cells || !cells.length) return;

      const sevCell = cells[0];
      const toolCell = cells[1];
      const pathCell = cells[4];

      // Severity -> badge
      if (sevCell) {
        const hasBadge = sevCell.querySelector(".vsp-badge-sev");
        if (!hasBadge) {
          const raw = (sevCell.textContent || "").trim();
          if (raw) {
            const sev = raw.toUpperCase();
            const span = document.createElement("span");
            span.textContent = sev;
            span.className =
              "vsp-badge vsp-badge-sev vsp-badge-sev-" + sev.toLowerCase();
            sevCell.textContent = "";
            sevCell.appendChild(span);
          }
        }
      }

      // Tool -> badge
      if (toolCell) {
        const hasTool = toolCell.querySelector(".vsp-badge-tool");
        if (!hasTool) {
          const tool = (toolCell.textContent || "").trim();
          if (tool) {
            const span = document.createElement("span");
            span.textContent = tool;
            span.className = "vsp-badge vsp-badge-tool";
            toolCell.textContent = "";
            toolCell.appendChild(span);
          }
        }
      }

      // Path -> rút gọn + tooltip
      if (pathCell && !pathCell.dataset.vspShortened) {
        const full = (pathCell.textContent || "").trim();
        if (full.length > 70) {
          const short = "…" + full.slice(-65);
          pathCell.textContent = short;
          pathCell.title = full;
        }
        pathCell.dataset.vspShortened = "1";
      }
    });
  }

  function enhanceDataSourceTab() {
    const tbody =
      document.getElementById("vsp-datasource-tbody") ||
      document.getElementById("vsp-ds-tbody");
    if (!tbody) {
      console.log(
        LOG_PREFIX,
        "Không thấy tbody Data Source (#vsp-datasource-tbody / #vsp-ds-tbody)."
      );
      return;
    }

    const table = tbody.closest("table");
    if (table && !table.classList.contains("vsp-table-hover")) {
      table.classList.add("vsp-table-hover");
    }

    // Style lần đầu
    styleDataSourceRows(tbody);

    // Bắt async update từ /api/vsp/datasource_v2
    const observer = new MutationObserver(function () {
      styleDataSourceRows(tbody);
    });
    observer.observe(tbody, { childList: true });

    console.log(LOG_PREFIX, "Data Source polish ready (MutationObserver).");
  }

  /*  Settings & Rules – toast  */

  function wireSettingsAndRulesToasts() {
    const settingsSave = document.getElementById("vsp-settings-save");
    if (settingsSave && !settingsSave.classList.contains("vsp-btn-primary")) {
      settingsSave.classList.add("vsp-btn-primary", "vsp-btn");
    }

    const rulesSave = document.getElementById("vsp-rules-save");
    if (rulesSave && !rulesSave.classList.contains("vsp-btn-primary")) {
      rulesSave.classList.add("vsp-btn-primary", "vsp-btn");
    }

    if (settingsSave) {
      settingsSave.addEventListener("click", function () {
        showToast("Đang lưu settings_v1.json ...", "info");
        setTimeout(function () {
          showToast("Settings đã được gửi lên server.", "success");
        }, 700);
      });
    }

    if (rulesSave) {
      rulesSave.addEventListener("click", function () {
        showToast("Đang lưu rule_overrides_v1.json ...", "info");
        setTimeout(function () {
          showToast("Rule overrides đã được gửi lên server.", "success");
        }, 700);
      });
    }
  }

  ready(function () {
    console.log(
      LOG_PREFIX,
      "Khởi tạo polish V2 cho Runs / Data / Settings / Rules."
    );
    try {
      enhanceRunsTab();
    } catch (e) {
      console.error(LOG_PREFIX, "Lỗi enhanceRunsTab:", e);
    }
    try {
      enhanceDataSourceTab();
    } catch (e) {
      console.error(LOG_PREFIX, "Lỗi enhanceDataSourceTab:", e);
    }
    try {
      wireSettingsAndRulesToasts();
    } catch (e) {
      console.error(LOG_PREFIX, "Lỗi wireSettingsAndRulesToasts:", e);
    }
  });
})();
