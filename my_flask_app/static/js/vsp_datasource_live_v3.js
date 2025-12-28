/**
 * VSP 2025 – Data Source Live (v3)
 * Ghép data thật từ /api/vsp/datasource_v2 vào layout TAB 3 – Data Source.
 *
 * Layout target:
 *   - Tab:   <section id="tab-data" ...>
 *   - Table: <table class="vsp-table" id="tblTopRisk">...</table>
 */

(function () {
  const API_URL = "/api/vsp/datasource_v2";

  function log(...args) {
    console.log("[VSP][DATASOURCE_V3]", ...args);
  }

  function mapSeverityClass(sev) {
    const s = (sev || "").toUpperCase();
    switch (s) {
      case "CRITICAL": return "critical";
      case "HIGH":     return "high";
      case "MEDIUM":   return "medium";
      case "LOW":      return "low";
      case "INFO":     return "info";
      case "TRACE":    return "trace";
      default:         return "info";
    }
  }

  function shortenPath(path) {
    if (!path) return "–";
    const s = String(path);
    if (s.length <= 70) return s;
    return "…" + s.slice(-70);
  }

  function safe(obj, path, fallback = null) {
    try {
      return path.split(".").reduce(
        (acc, key) => (acc && acc[key] != null ? acc[key] : null),
        obj
      ) ?? fallback;
    } catch {
      return fallback;
    }
  }

  async function fetchDataSource(params) {
    const url = new URL(API_URL, window.location.origin);
    url.searchParams.set("limit", params?.limit || "200");
    if (params?.severity) url.searchParams.set("severity", params.severity);
    if (params?.tool)     url.searchParams.set("tool", params.tool);
    if (params?.text)     url.searchParams.set("text", params.text);

    log("Fetch", url.toString());
    const res = await fetch(url.toString(), { method: "GET" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    return res.json();
  }

  function renderTable(items) {
    const table = document.getElementById("tblTopRisk");
    if (!table) {
      log("Không tìm thấy #tblTopRisk, bỏ qua render.");
      return;
    }
    const tbody = table.querySelector("tbody") || table.createTBody();

    if (!Array.isArray(items) || items.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="11" style="text-align:center; font-size:11px; color:#9ca3af;">
            Không có findings (hoặc filter đang loại hết kết quả).
          </td>
        </tr>`;
      return;
    }

    const rows = items.map((it) => {
      const sevEff = it.severity_effective || it.severity || it.severity_raw || "INFO";
      const sevRaw = it.severity_raw || sevEff;
      const sevClass = mapSeverityClass(sevEff);

      const tool = it.tool || "–";
      const file = shortenPath(it.file);
      const line = it.line != null ? it.line : "–";

      const extra = it.extra || {};
      const ruleId =
        extra.rule_id ||
        extra.RuleID ||
        extra.rule ||
        extra.ruleID ||
        extra.check_id ||
        extra.id ||
        "–";

      const message = it.message || it.title || "–";
      const cwe = it.cwe || safe(extra, "cwe_id", "–");
      const cve = safe(it, "vuln.cve_id", safe(extra, "cve_id", "–"));

      const moduleName = it.module || safe(extra, "module", "–");

      const tags = [];
      if (it.overridden) {
        tags.push(`Overridden (${it.override_rule_id || "rule"})`);
      }
      if (safe(it, "vuln.cvss_score") != null) {
        tags.push(`CVSS ${safe(it, "vuln.cvss_score")}`);
      }
      if (safe(it, "asset.package_name")) {
        tags.push("Pkg");
      }

      const sevBadge = `
        <span class="badge-sev ${sevClass}">
          ${sevEff}
        </span>
        ${
          sevEff !== sevRaw
            ? `<span style="display:inline-block; margin-left:4px; font-size:9px; color:#9ca3af;">
                 raw: ${sevRaw}
               </span>`
            : ""
        }
      `;

      const fixShort = safe(it, "fix_guide.short_title") || "–";

      const tagsHtml = tags.length
        ? tags
            .map(
              (t) =>
                `<span class="tag-soft" style="padding:2px 6px; font-size:9px;">${t}</span>`
            )
            .join(" ")
        : "–";

      return `
        <tr>
          <td>${sevBadge}</td>
          <td>${tool}</td>
          <td title="${it.file || ""}">${file}</td>
          <td>${line}</td>
          <td>${ruleId}</td>
          <td title="${message}">${message}</td>
          <td>${cwe}</td>
          <td>${cve}</td>
          <td>${moduleName}</td>
          <td>${fixShort}</td>
          <td>${tagsHtml}</td>
        </tr>
      `;
    });

    tbody.innerHTML = rows.join("");
  }

  async function initDataSourceOnce() {
    const container = document.getElementById("tab-data");
    if (!container) {
      log("Không thấy #tab-data – layout hiện tại không có TAB Data Source.");
      return;
    }

    const table = document.getElementById("tblTopRisk");
    if (!table) {
      log("Không thấy #tblTopRisk trong TAB Data Source.");
    }

    try {
      const tbody = table?.querySelector("tbody") || table?.createTBody();
      if (tbody) {
        tbody.innerHTML = `
          <tr>
            <td colspan="11" style="text-align:center; font-size:11px; color:#9ca3af;">
              Đang tải dữ liệu unified findings từ VSP backend...
            </td>
          </tr>`;
      }

      const json = await fetchDataSource({ limit: 200 });
      log("API datasource_v2:", json);

      const items = Array.isArray(json.items) ? json.items : [];
      renderTable(items);
    } catch (e) {
      console.error("[VSP][DATASOURCE_V3] Error:", e);
      const tbody = document.querySelector("#tblTopRisk tbody");
      if (tbody) {
        tbody.innerHTML = `
          <tr>
            <td colspan="11" style="text-align:center; font-size:11px; color:#f97373;">
              Lỗi tải Data Source: ${(e && e.message) || e}. Kiểm tra /api/vsp/datasource_v2.
            </td>
          </tr>`;
      }
    }
  }

  function wireTabActivation() {
    const tabBtn = document.querySelector('.vsp-tab-btn[data-tab="tab-data"]');
    const tabPane = document.getElementById("tab-data");
    if (!tabPane) {
      log("Không có tab-pane #tab-data trong layout hiện tại.");
      return;
    }

    let loaded = false;

    function tryInit() {
      if (loaded) return;
      loaded = true;
      initDataSourceOnce();
    }

    if (tabPane.classList.contains("active")) {
      tryInit();
    }

    if (tabBtn) {
      tabBtn.addEventListener("click", () => {
        tryInit();
      });
    } else {
      // fallback: nếu không có tab-btn, vẫn init sau 1.5s
      setTimeout(tryInit, 1500);
    }
  }

  function start() {
    try {
      wireTabActivation();
    } catch (e) {
      console.error("[VSP][DATASOURCE_V3] init error:", e);
    }
  }

  // Đảm bảo chạy cả khi script load sau DOMContentLoaded
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
