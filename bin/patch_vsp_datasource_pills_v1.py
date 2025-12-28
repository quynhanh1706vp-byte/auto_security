from pathlib import Path

target = Path("static/js/vsp_datasource_v1.js")
text = target.read_text(encoding="utf-8")

marker = "// VSP_DS_PILLS_V1"
if marker in text:
    print("[INFO] Đã có block VSP_DS_PILLS_V1, bỏ qua.")
else:
    patch = r"""
// VSP_DS_PILLS_V1
// Tự động map severity -> pill + format cột Overridden (Yes/No) sau khi bảng render.
(function () {
  function normalizeSeverity(raw) {
    if (!raw) return "";
    return String(raw).trim().toUpperCase();
  }

  function severityToClass(sev) {
    switch (sev) {
      case "CRITICAL":
        return "vsp-pill--critical";
      case "HIGH":
        return "vsp-pill--high";
      case "MEDIUM":
        return "vsp-pill--medium";
      case "LOW":
        return "vsp-pill--low";
      case "INFO":
        return "vsp-pill--info";
      case "TRACE":
        return "vsp-pill--trace";
      default:
        return "";
    }
  }

  function enhanceDatasourceTable() {
    const table = document.querySelector(".vsp-ds-table");
    if (!table) return;
    const tbody = table.tBodies && table.tBodies[0];
    if (!tbody) return;

    const rows = tbody.querySelectorAll("tr");
    rows.forEach((tr) => {
      const tds = tr.querySelectorAll("td");
      if (!tds.length) return;

      // Giả định: cột 1 = Severity, cột cuối = Overridden (true/false).
      const severityTd = tds[0];
      const overriddenTd = tds[tds.length - 1];

      // ----- Severity pill -----
      const rawSev = severityTd.textContent || "";
      const sev = normalizeSeverity(rawSev);
      const sevClass = severityToClass(sev);

      if (sev) {
        severityTd.innerHTML = "";
        const span = document.createElement("span");
        span.className = "vsp-pill vsp-pill--severity " + sevClass;
        span.textContent = sev;
        severityTd.appendChild(span);
      }

      // ----- Overridden Yes/No -----
      if (overriddenTd) {
        const raw = (overriddenTd.textContent || "").trim().toLowerCase();
        let isYes = false;
        if (["true", "1", "yes", "y"].includes(raw)) {
          isYes = True
        }
        // Cho cả trường hợp BE trả "YES"/"NO".
        if (["yes"].includes(raw)) {
          isYes = True
        }

        overriddenTd.innerHTML = "";
        const span = document.createElement("span");
        span.className =
          "vsp-pill vsp-pill--override " +
          (isYes ? "vsp-pill--override-yes" : "vsp-pill--override-no");
        span.textContent = isYes ? "Yes" : "No";
        overriddenTd.appendChild(span);
      }
    });
  }

  function setupObserver() {
    const table = document.querySelector(".vsp-ds-table");
    if (!table) return;
    const tbody = table.tBodies && table.tBodies[0];
    if (!tbody) return;

    // Chạy lần đầu.
    enhanceDatasourceTable();

    // Quan sát khi JS khác thay đổi tbody (paging, filter, reload API).
    const observer = new MutationObserver(function () {
      enhanceDatasourceTable();
    });

    observer.observe(tbody, {
      childList: true,
      subtree: true,
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    // Đợi một chút cho JS DataSource load xong.
    setTimeout(setupObserver, 400);
  });
})();
"""

    target.write_text(text + "\n" + patch, encoding="utf-8")
    print("[OK] Đã append block VSP_DS_PILLS_V1 vào static/js/vsp_datasource_v1.js")
