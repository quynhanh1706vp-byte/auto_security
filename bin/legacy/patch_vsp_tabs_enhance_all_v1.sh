#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/static/js/vsp_console_patch_v1.js"

echo "[VSP_TABS_ENHANCE] ROOT   = ${ROOT}"
echo "[VSP_TABS_ENHANCE] TARGET = ${TARGET}"

if [ ! -f "${TARGET}" ]; then
  echo "[VSP_TABS_ENHANCE][ERR] Không tìm thấy ${TARGET}"
  exit 1
fi

BACKUP="${TARGET}.bak_tabs_enhance_v1_$(date +%Y%m%d_%H%M%S)"
cp "${TARGET}" "${BACKUP}"
echo "[VSP_TABS_ENHANCE] Đã backup thành ${BACKUP}"

cat >> "${TARGET}" << 'JS'

// ===============================================
// [VSP_TABS_ENHANCE_v1]
// Decorate 4 tabs còn lại: Runs, DataSource,
// Settings, Rule Overrides với KPI header
// ===============================================
(function () {
  const LOG = (...args) => console.log("[VSP_TABS_ENHANCE]", ...args);

  function onReadyTabsEnhance(fn) {
    if (document.readyState === "complete" || document.readyState === "interactive") {
      fn();
    } else {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    }
  }

  // ------ Helper: ensure header container trong 1 tab ------
  function ensureTabHeader(tabEl, title, subtitle) {
    if (!tabEl) return null;

    let header = tabEl.querySelector(".vsp-tab-header");
    if (!header) {
      header = document.createElement("div");
      header.className = "vsp-tab-header vsp-tab-header-grid";
      tabEl.prepend(header);
    }

    // Nếu chưa có title thì thêm 1 lần
    if (!header.querySelector(".vsp-tab-title")) {
      const titleBox = document.createElement("div");
      titleBox.className = "vsp-tab-title";
      const h2 = document.createElement("h2");
      h2.textContent = title;
      const p = document.createElement("p");
      p.textContent = subtitle || "";
      titleBox.appendChild(h2);
      titleBox.appendChild(p);
      header.appendChild(titleBox);
    }

    // Khu KPI row
    let kpiRow = header.querySelector(".vsp-tab-kpi-row");
    if (!kpiRow) {
      kpiRow = document.createElement("div");
      kpiRow.className = "vsp-tab-kpi-row";
      header.appendChild(kpiRow);
    }
    return kpiRow;
  }

  function makeKpiChip(label, value, extra) {
    const div = document.createElement("div");
    div.className = "vsp-kpi-chip";

    const spanLabel = document.createElement("div");
    spanLabel.className = "vsp-kpi-chip-label";
    spanLabel.textContent = label;

    const spanVal = document.createElement("div");
    spanVal.className = "vsp-kpi-chip-value";
    spanVal.textContent = value;

    div.appendChild(spanLabel);
    div.appendChild(spanVal);

    if (extra) {
      const spanExtra = document.createElement("div");
      spanExtra.className = "vsp-kpi-chip-extra";
      spanExtra.textContent = extra;
      div.appendChild(spanExtra);
    }

    return div;
  }

  // ------------- Runs & Reports tab -------------
  async function enhanceRunsTab() {
    const tab = document.getElementById("vsp-tab-runs");
    if (!tab) {
      LOG("Không thấy tab Runs (#vsp-tab-runs)");
      return;
    }

    let kpiRow = ensureTabHeader(
      tab,
      "Runs & Reports",
      "Lịch sử các lần scan · chọn 1 run để xem chi tiết."
    );
    if (!kpiRow) return;

    // Chỉ thêm 1 lần
    if (kpiRow.dataset.enhanced === "1") {
      LOG("Runs tab đã enhanced, bỏ qua.");
      return;
    }

    try {
      const res = await fetch("/api/vsp/runs_index_v3?limit=50", { cache: "no-store" });
      if (!res.ok) {
        LOG("HTTP error runs_index_v3:", res.status);
        return;
      }
      const data = await res.json();

      const kpi = data.kpi || {};
      const items = Array.isArray(data.items) ? data.items : [];

      const totalRuns = kpi.total_runs || items.length || 0;
      const avgLastN = kpi.avg_findings_per_run_last_n || 0;
      const lastN = kpi.last_n || (items.length || 0);

      const lastRun = items[0] || {};
      const lastRunId = lastRun.run_id || "N/A";
      const lastRunTotal = lastRun.total_findings || lastRun.total || 0;

      kpiRow.appendChild(
        makeKpiChip("Total runs", String(totalRuns), `Last N = ${lastN}`)
      );
      kpiRow.appendChild(
        makeKpiChip("Avg findings (last N)", String(Math.round(avgLastN)), "")
      );
      kpiRow.appendChild(
        makeKpiChip("Latest run", lastRunId, `Findings = ${lastRunTotal}`)
      );

      kpiRow.dataset.enhanced = "1";

      LOG("Enhanced Runs tab KPI:", {
        totalRuns,
        avgLastN,
        lastN,
        lastRunId,
        lastRunTotal,
      });
    } catch (e) {
      LOG("Exception enhanceRunsTab:", e);
    }
  }

  // ------------- Data Source tab -------------
  async function enhanceDatasourceTab() {
    const tab = document.getElementById("vsp-tab-datasource");
    if (!tab) {
      LOG("Không thấy tab DataSource (#vsp-tab-datasource)");
      return;
    }

    let kpiRow = ensureTabHeader(
      tab,
      "Data Source",
      "Bảng chi tiết các findings đã unify từ nhiều tool."
    );
    if (!kpiRow) return;

    if (kpiRow.dataset.enhanced === "1") {
      LOG("DataSource tab đã enhanced, bỏ qua.");
      return;
    }

    try {
      const res = await fetch("/api/vsp/datasource_v2?limit=1", { cache: "no-store" });
      if (!res.ok) {
        LOG("HTTP error datasource_v2:", res.status);
        return;
      }
      const data = await res.json();
      if (!data || data.ok === false) {
        LOG("Datasource trả ok=false hoặc rỗng:", data);
      }

      const total = data.total || 0;
      const bySeverity = data.by_severity || {};
      const crit = bySeverity.CRITICAL || 0;
      const high = bySeverity.HIGH || 0;
      const med = bySeverity.MEDIUM || 0;

      kpiRow.appendChild(
        makeKpiChip("Total findings (all tools)", String(total), "")
      );
      kpiRow.appendChild(
        makeKpiChip("Critical / High", `${crit} / ${high}`, "Tập trung xử lý nhóm này trước.")
      );
      kpiRow.appendChild(
        makeKpiChip("Medium", String(med), "Ưu tiên theo business impact.")
      );

      kpiRow.dataset.enhanced = "1";

      LOG("Enhanced DataSource tab KPI:", { total, bySeverity });
    } catch (e) {
      LOG("Exception enhanceDatasourceTab:", e);
    }
  }

  // ------------- Settings tab -------------
  async function enhanceSettingsTab() {
    const tab = document.getElementById("vsp-tab-settings");
    if (!tab) {
      LOG("Không thấy tab Settings (#vsp-tab-settings)");
      return;
    }

    let kpiRow = ensureTabHeader(
      tab,
      "Settings & Profiles",
      "Cấu hình tool, profile scan và policy gate."
    );
    if (!kpiRow) return;

    if (kpiRow.dataset.enhanced === "1") {
      LOG("Settings tab đã enhanced, bỏ qua.");
      return;
    }

    try {
      const res = await fetch("/api/vsp/settings_ui_v1", { cache: "no-store" });
      if (!res.ok) {
        LOG("HTTP error settings_ui_v1:", res.status);
        return;
      }
      const data = await res.json();
      const settings = data.settings || {};

      const gate = settings.gate_policy || {};
      const maxCrit = gate.max_critical;
      const maxHigh = gate.max_high;

      const tools = settings.tools_enabled || settings.tools || [];
      const toolsLabel = Array.isArray(tools) && tools.length
        ? tools.join(", ")
        : "Semgrep, Gitleaks, KICS, CodeQL, Bandit, Trivy, Syft, Grype";

      kpiRow.appendChild(
        makeKpiChip("Gate policy", "CRIT = 0", `HIGH ≤ ${typeof maxHigh === "number" ? maxHigh : 10}`)
      );
      kpiRow.appendChild(
        makeKpiChip("Tools enabled", String(Array.isArray(tools) ? tools.length : 8), toolsLabel)
      );

      kpiRow.dataset.enhanced = "1";

      LOG("Enhanced Settings tab KPI:", { gate, tools });
    } catch (e) {
      LOG("Exception enhanceSettingsTab:", e);
    }
  }

  // ------------- Rule Overrides / Rules tab -------------
  async function enhanceRulesTab() {
    // Tùy bản, có thể là vsp-tab-rules hoặc vsp-tab-rule-overrides
    const tab =
      document.getElementById("vsp-tab-rule-overrides") ||
      document.getElementById("vsp-tab-rules");
    if (!tab) {
      LOG("Không thấy tab Rule Overrides (#vsp-tab-rule-overrides / #vsp-tab-rules)");
      return;
    }

    let kpiRow = ensureTabHeader(
      tab,
      "Rule Overrides",
      "Quản lý các ngoại lệ, suppression và tuning rule cho tool."
    );
    if (!kpiRow) return;

    if (kpiRow.dataset.enhanced === "1") {
      LOG("Rules tab đã enhanced, bỏ qua.");
      return;
    }

    try {
      const res = await fetch("/api/vsp/rule_overrides_ui_v1", { cache: "no-store" });
      if (!res.ok) {
        LOG("HTTP error rule_overrides_ui_v1:", res.status);
        return;
      }
      const data = await res.json();

      const total = data.total || 0;
      const active = data.active || data.enabled || 0;
      const byTool = data.by_tool || {};

      const toolsCount = Object.keys(byTool).length;
      const toolsList = Object.keys(byTool).slice(0, 4).join(", ");

      kpiRow.appendChild(
        makeKpiChip("Total overrides", String(total), `Active = ${active}`)
      );
      kpiRow.appendChild(
        makeKpiChip("Tools with overrides", String(toolsCount), toolsList || "N/A")
      );

      kpiRow.dataset.enhanced = "1";

      LOG("Enhanced Rules tab KPI:", { total, active, byTool });
    } catch (e) {
      LOG("Exception enhanceRulesTab:", e);
    }
  }

  onReadyTabsEnhance(() => {
    try {
      enhanceRunsTab();
      enhanceDatasourceTab();
      enhanceSettingsTab();
      enhanceRulesTab();
    } catch (e) {
      LOG("Exception top-level:", e);
    }
  });
})();
JS

echo "[VSP_TABS_ENHANCE] Đã append JS vào ${TARGET}"
