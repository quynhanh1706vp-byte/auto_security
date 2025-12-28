#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/static/js/vsp_console_patch_v1.js"

echo "[VSP_TABS_ENHANCE_V2] ROOT   = ${ROOT}"
echo "[VSP_TABS_ENHANCE_V2] TARGET = ${TARGET}"

if [ ! -f "${TARGET}" ]; then
  echo "[VSP_TABS_ENHANCE_V2][ERR] Không tìm thấy ${TARGET}"
  exit 1
fi

BACKUP="${TARGET}.bak_tabs_enhance_v2_$(date +%Y%m%d_%H%M%S)"
cp "${TARGET}" "${BACKUP}"
echo "[VSP_TABS_ENHANCE_V2] Đã backup thành ${BACKUP}"

cat >> "${TARGET}" << 'JS'
// ====================================================
// [VSP_TABS_ENHANCE_v2]
// Thêm header + KPI cho 4 tab: Runs, Data, Settings,
// Rule Overrides. Dùng MutationObserver chờ tab sẵn sàng.
// ====================================================
(function () {
  const LOG = (...args) => console.log("[VSP_TABS_ENHANCE_V2]", ...args);

  function whenReady(fn) {
    if (document.readyState === "complete" || document.readyState === "interactive") {
      fn();
    } else {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    }
  }

  // ---- Helper: chờ cho tới khi có element với id ----
  function waitForEl(id, cb) {
    const existing = document.getElementById(id);
    if (existing) {
      cb(existing);
      return;
    }
    const maxTries = 40;
    let tries = 0;

    const obs = new MutationObserver(() => {
      const el = document.getElementById(id);
      if (el) {
        obs.disconnect();
        cb(el);
      } else if (++tries >= maxTries) {
        obs.disconnect();
        LOG("Timeout chờ element", id);
      }
    });

    obs.observe(document.body, { childList: true, subtree: true });
  }

  function ensureTabHeader(tabEl, title, subtitle) {
    if (!tabEl) return null;

    let header = tabEl.querySelector(".vsp-tab-header");
    if (!header) {
      header = document.createElement("div");
      header.className = "vsp-tab-header vsp-tab-header-grid";
      tabEl.prepend(header);
    }

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

    const lab = document.createElement("div");
    lab.className = "vsp-kpi-chip-label";
    lab.textContent = label;

    const val = document.createElement("div");
    val.className = "vsp-kpi-chip-value";
    val.textContent = value;

    div.appendChild(lab);
    div.appendChild(val);

    if (extra) {
      const ext = document.createElement("div");
      ext.className = "vsp-kpi-chip-extra";
      ext.textContent = extra;
      div.appendChild(ext);
    }
    return div;
  }

  // ------------- Runs & Reports ----------------
  async function enhanceRuns(tab) {
    const kpiRow = ensureTabHeader(
      tab,
      "Runs & Reports",
      "Lịch sử scan · chọn 1 run để xem / export."
    );
    if (!kpiRow || kpiRow.dataset.enhanced === "1") return;

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
      const lastN = kpi.last_n || (items.length || 0);
      const avgLastN = kpi.avg_findings_per_run_last_n || 0;

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
      LOG("Runs tab enhanced.");
    } catch (e) {
      LOG("Runs enhance error:", e);
    }
  }

  // ------------- Data Source -------------------
  async function enhanceDataSource(tab) {
    const kpiRow = ensureTabHeader(
      tab,
      "Data Source",
      "Bảng chi tiết findings unify từ nhiều tool."
    );
    if (!kpiRow || kpiRow.dataset.enhanced === "1") return;

    try {
      const res = await fetch("/api/vsp/datasource_v2?limit=1", { cache: "no-store" });
      if (!res.ok) {
        LOG("HTTP error datasource_v2:", res.status);
        return;
      }
      const data = await res.json();
      const total = data.total || 0;
      const sev = data.by_severity || {};
      const crit = sev.CRITICAL || 0;
      const high = sev.HIGH || 0;
      const med = sev.MEDIUM || 0;

      kpiRow.appendChild(
        makeKpiChip("Total findings", String(total), "Từ tất cả tools")
      );
      kpiRow.appendChild(
        makeKpiChip("Critical / High", `${crit} / ${high}`, "Xử lý nhóm này trước")
      );
      kpiRow.appendChild(
        makeKpiChip("Medium", String(med), "Ưu tiên theo business impact")
      );

      kpiRow.dataset.enhanced = "1";
      LOG("DataSource tab enhanced.");
    } catch (e) {
      LOG("DataSource enhance error:", e);
    }
  }

  // ------------- Settings ----------------------
  async function enhanceSettings(tab) {
    const kpiRow = ensureTabHeader(
      tab,
      "Settings & Profiles",
      "Cấu hình tool, profile scan, gate policy."
    );
    if (!kpiRow || kpiRow.dataset.enhanced === "1") return;

    try {
      const res = await fetch("/api/vsp/settings_ui_v1", { cache: "no-store" });
      if (!res.ok) {
        LOG("HTTP error settings_ui_v1:", res.status);
        return;
      }
      const data = await res.json();
      const settings = data.settings || {};

      const gate = settings.gate_policy || {};
      const maxHigh = typeof gate.max_high === "number" ? gate.max_high : 10;

      const tools = settings.tools_enabled || settings.tools || [];
      const arr = Array.isArray(tools) ? tools : [];
      const toolsLabel = arr.length
        ? arr.join(", ")
        : "Semgrep, Gitleaks, KICS, CodeQL, Bandit, Trivy, Syft, Grype";

      kpiRow.appendChild(
        makeKpiChip("Gate policy", "CRIT = 0", `HIGH ≤ ${maxHigh}`)
      );
      kpiRow.appendChild(
        makeKpiChip("Tools enabled", String(arr.length || 8), toolsLabel)
      );

      kpiRow.dataset.enhanced = "1";
      LOG("Settings tab enhanced.");
    } catch (e) {
      LOG("Settings enhance error:", e);
    }
  }

  // ------------- Rules / Overrides -------------
  async function enhanceRules(tab) {
    const kpiRow = ensureTabHeader(
      tab,
      "Rule Overrides",
      "Quản lý ngoại lệ, suppression, tuning rule."
    );
    if (!kpiRow || kpiRow.dataset.enhanced === "1") return;

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
      const tools = Object.keys(byTool);
      const toolsList = tools.slice(0, 4).join(", ");

      kpiRow.appendChild(
        makeKpiChip("Total overrides", String(total), `Active = ${active}`)
      );
      kpiRow.appendChild(
        makeKpiChip("Tools with overrides", String(tools.length), toolsList || "N/A")
      );

      kpiRow.dataset.enhanced = "1";
      LOG("Rules tab enhanced.");
    } catch (e) {
      LOG("Rules enhance error:", e);
    }
  }

  whenReady(function () {
    LOG("Init tab enhancements V2...");

    waitForEl("vsp-tab-runs", enhanceRuns);
    waitForEl("vsp-tab-datasource", enhanceDataSource);
    waitForEl("vsp-tab-settings", enhanceSettings);

    // rules tab id có thể là vsp-tab-rule-overrides hoặc vsp-tab-rules
    waitForEl("vsp-tab-rule-overrides", enhanceRules);
    waitForEl("vsp-tab-rules", enhanceRules);
  });
})();
JS

echo "[VSP_TABS_ENHANCE_V2] Đã append JS V2 vào ${TARGET}"
