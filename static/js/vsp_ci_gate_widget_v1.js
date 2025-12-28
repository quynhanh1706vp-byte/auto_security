(function() {
  const LOG = "[VSP_CI_GATE]";

  function gotoRunsForRunId(runId) {
    try {
      // Lưu lại cho script khác dùng nếu cần
      window.VSP_CI_GATE_LAST_RUN_ID = runId;

      // Chuyển sang tab Runs & Reports nếu tìm thấy nút tab
      try {
        const runsTabBtn =
          document.querySelector('[data-vsp-tab-target="#vsp-tab-runs"]') ||
          document.querySelector('[data-bs-target="#vsp-tab-runs"]') ||
          document.querySelector('button#vsp-tab-runs') ||
          document.querySelector('a[href="#vsp-tab-runs"]');
        if (runsTabBtn) {
          runsTabBtn.click();
        }
      } catch (e) {
        console.warn(LOG, "Không tìm thấy nút tab Runs, bỏ qua.", e);
      }

      // Filter theo run-id nếu có ô filter
      try {
        const filterInput =
          document.querySelector('input[data-vsp-runs-filter="run-id"]') ||
          document.querySelector('input#vsp-runs-filter-run-id') ||
          document.querySelector('input[name="run_id_filter"]');
        if (filterInput) {
          filterInput.value = runId;
          filterInput.dispatchEvent(new Event("input", { bubbles: true }));
        }
      } catch (e) {
        console.warn(LOG, "Không autofilter được run-id, bỏ qua.", e);
      }

      // Hash CHỈ dùng để chọn tab, không nhét runId vào nữa
      try {
        window.location.hash = "#runs";
      } catch (e) {
        console.warn(LOG, "Không set hash được", e);
      }
    } catch (err) {
      console.error(LOG, "gotoRunsForRunId error:", err);
    }
  }

  function createWidget(data) {
    if (!data || !data.ok) {
      console.warn(LOG, "No data or ok=false", data);
      return;
    }

    let existing = document.getElementById("vsp-ci-gate-widget");
    if (existing) existing.remove();

    const hasFindings = !!data.has_findings;
    const total = data.total_findings || 0;
    const runId = data.run_id || data.ci_run_dir || "—";
    const sev = data.by_severity || {};

    const c = sev.CRITICAL || 0;
    const h = sev.HIGH || 0;
    const m = sev.MEDIUM || 0;
    const l = sev.LOW || 0;
    const info = sev.INFO || 0;
    const trace = sev.TRACE || 0;

    const severities = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", trace:"TRACE"];

    // Policy FAIL / WARN / PASS
    let status = "PASS";
    let statusLabel = "PASS";
    let borderColor = "#22c55e";
    let badgeBg = "rgba(34,197,94,0.12)";
    let badgeColor = "#4ade80";

    if (c > 0 || h > 10) {
      status = "FAIL";
      statusLabel = "FAILED";
      borderColor = "#f97373";
      badgeBg = "rgba(248,113,113,0.12)";
      badgeColor = "#f97373";
    } else if (h === 0 && c === 0 && (m > 0 || l > 0)) {
      status = "WARN";
      statusLabel = "PASS (MED/LOW)";
      borderColor = "#fbbf24";
      badgeBg = "rgba(251,191,36,0.12)";
      badgeColor = "#fbbf24";
    }

    const wrapper = document.createElement("div");
    wrapper.id = "vsp-ci-gate-widget";
    Object.assign(wrapper.style, {
      position: "fixed",
      right: "20px",
      bottom: "20px",
      zIndex: 9999,
      minWidth: "260px",
      maxWidth: "320px",
      background: "#020617",
      color: "#e5e7eb",
      borderRadius: "12px",
      boxShadow: "0 10px 30px rgba(15,23,42,0.8)",
      padding: "14px 16px",
      fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, 'Inter', sans-serif",
      border: "1px solid " + borderColor,
      fontSize: "13px",
      cursor: "default"
    });

    wrapper.title = "Data from /api/vsp/ci_snapshot_latest\nPolicy: FAIL if CRITICAL>0 or HIGH>10";

    const header = document.createElement("div");
    header.style.display = "flex";
    header.style.alignItems = "center";
    header.style.justifyContent = "space-between";
    header.style.marginBottom = "6px";

    const title = document.createElement("div");
    title.textContent = "CI Gate – Latest Run";
    title.style.fontWeight = "600";
    title.style.fontSize = "13px";
    header.appendChild(title);

    const statusBadge = document.createElement("div");
    statusBadge.textContent = statusLabel;
    Object.assign(statusBadge.style, {
      padding: "2px 8px",
      borderRadius: "999px",
      fontSize: "11px",
      fontWeight: "600",
      letterSpacing: "0.04em",
      background: badgeBg,
      color: badgeColor
    });
    header.appendChild(statusBadge);
    wrapper.appendChild(header);

    const runLine = document.createElement("div");
    runLine.textContent = runId;
    runLine.style.fontSize = "11px";
    runLine.style.color = "#9ca3af";
    runLine.style.marginBottom = "10px";
    wrapper.appendChild(runLine);

    const totalRow = document.createElement("div");
    totalRow.style.display = "flex";
    totalRow.style.alignItems = "baseline";
    totalRow.style.marginBottom = "8px";

    const totalLabel = document.createElement("span");
    totalLabel.textContent = "Total findings:";
    totalLabel.style.fontSize = "11px";
    totalLabel.style.color = "#9ca3af";

    const totalVal = document.createElement("span");
    totalVal.textContent = " " + total;
    totalVal.style.fontSize = "16px";
    totalVal.style.fontWeight = "700";
    totalVal.style.marginLeft = "4px";
    totalVal.style.color = status === "FAIL"
      ? "#f97316"
      : (status === "WARN" ? "#fbbf24" : "#22c55e");

    totalRow.appendChild(totalLabel);
    totalRow.appendChild(totalVal);
    wrapper.appendChild(totalRow);

    const sevRow = document.createElement("div");
    sevRow.style.display = "flex";
    sevRow.style.flexWrap = "wrap";
    sevRow.style.gap = "4px";

    const sevColors = {
      CRITICAL: "#f97373",
      HIGH: "#fb923c",
      MEDIUM: "#eab308",
      LOW: "#22c55e",
      INFO: "#38bdf8",
  TRACE:"#a855f7",
    };

    severities.forEach((name) => {
      const v =
        name === "CRITICAL" ? c :
        name === "HIGH" ? h :
        name === "MEDIUM" ? m :
        name === "LOW" ? l :
        name === "INFO" ? info :
        trace;
      const pill = document.createElement("div");
      pill.textContent = name[0] + ": " + v;
      Object.assign(pill.style, {
        fontSize: "10px",
        padding: "2px 6px",
        borderRadius: "999px",
        background: "rgba(15,23,42,0.9)",
        border: "1px solid " + (sevColors[name] || "#4b5563"),
        color: sevColors[name] || "#e5e7eb"
      });
      sevRow.appendChild(pill);
    });

    wrapper.appendChild(sevRow);

    const footer = document.createElement("div");
    footer.style.marginTop = "8px";
    footer.style.display = "flex";
    footer.style.justifyContent = "space-between";
    footer.style.alignItems = "center";
    footer.style.fontSize = "10px";
    footer.style.color = "#6b7280";

    const sourceSpan = document.createElement("span");
    sourceSpan.textContent = "Source: CI";
    footer.appendChild(sourceSpan);

    const actions = document.createElement("div");
    actions.style.display = "flex";
    actions.style.alignItems = "center";
    actions.style.gap = "4px";

    const viewBtn = document.createElement("button");
    viewBtn.textContent = "View in Runs";
    Object.assign(viewBtn.style, {
      border: "none",
      background: "transparent",
      color: "#60a5fa",
      cursor: "pointer",
      fontSize: "10px",
      padding: "0 4px",
      textDecoration: "underline"
    });
    viewBtn.addEventListener("click", function(ev) {
      ev.stopPropagation();
      gotoRunsForRunId(runId);
    });
    actions.appendChild(viewBtn);

    const closeBtn = document.createElement("button");
    closeBtn.textContent = "×";
    Object.assign(closeBtn.style, {
      border: "none",
      background: "transparent",
      color: "#6b7280",
      cursor: "pointer",
      fontSize: "14px",
      padding: "0 4px"
    });
    closeBtn.addEventListener("click", function(ev) {
      ev.stopPropagation();
      wrapper.remove();
    });
    actions.appendChild(closeBtn);

    footer.appendChild(actions);
    wrapper.appendChild(footer);

    document.body.appendChild(wrapper);
  }

  async function loadSnapshot() {
    try {
      const res = await fetch("/api/vsp/ci_snapshot_latest", { cache: "no-store" });
      if (!res.ok) {
        console.warn(LOG, "HTTP", res.status);
        return;
      }
      const data = await res.json();
      console.log(LOG, "Snapshot", data);
      createWidget(data);
    } catch (e) {
      console.error(LOG, "Error loading CI snapshot:", e);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", loadSnapshot);
  } else {
    loadSnapshot();
  }
})();
