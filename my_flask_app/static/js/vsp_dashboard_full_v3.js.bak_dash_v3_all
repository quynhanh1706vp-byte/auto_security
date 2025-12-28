/**
 * VSP Dashboard binding v3
 * - Gọi /api/vsp/dashboard_v3
 * - Đổ KPI Total + 6 bucket severity
 * - Đổ Security Score + Top Tool + Top CWE + Top Module
 *
 * YÊU CẦU HTML CÓ CÁC ID:
 *   #vsp-kpi-total
 *   #vsp-kpi-critical
 *   #vsp-kpi-high
 *   #vsp-kpi-medium
 *   #vsp-kpi-low
 *   #vsp-kpi-info
 *   #vsp-kpi-trace
 *
 *   #vsp-kpi-security-score
 *   #vsp-kpi-top-tool
 *   #vsp-kpi-top-cwe
 *   #vsp-kpi-top-module
 */

(function () {
  const API_URL = "/api/vsp/dashboard_v3";

  function $(id) {
    return document.getElementById(id);
  }

  function safeNumber(v) {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }

  function formatNumber(n) {
    n = safeNumber(n);
    return n.toLocaleString("en-US");
  }

  function bindKpiCards(payload) {
    if (!payload) return;

    const sev = payload.by_severity || payload.severity || {};
    const total = safeNumber(payload.total_findings);

    const crit  = safeNumber(sev.CRITICAL);
    const high  = safeNumber(sev.HIGH);
    const med   = safeNumber(sev.MEDIUM);
    const low   = safeNumber(sev.LOW);
    const info  = safeNumber(sev.INFO);
    const trace = safeNumber(sev.TRACE);

    // ===== HÀNG KPI CHÍNH: Total + 6 bucket =====
    const elTotal   = $("vsp-kpi-total");
    const elCrit    = $("vsp-kpi-critical");
    const elHigh    = $("vsp-kpi-high");
    const elMed     = $("vsp-kpi-medium");
    const elLow     = $("vsp-kpi-low");
    const elInfo    = $("vsp-kpi-info");
    const elTrace   = $("vsp-kpi-trace");

    if (elTotal)  elTotal.textContent  = formatNumber(total);
    if (elCrit)   elCrit.textContent   = formatNumber(crit);
    if (elHigh)   elHigh.textContent   = formatNumber(high);
    if (elMed)    elMed.textContent    = formatNumber(med);
    if (elLow)    elLow.textContent    = formatNumber(low);
    if (elInfo)   elInfo.textContent   = formatNumber(info);
    if (elTrace)  elTrace.textContent  = formatNumber(trace);

    // Nếu anh muốn fill % hoặc tooltip thêm, có thể set data-* ở đây.
  }

  function bindAdvancedKpi(payload) {
    if (!payload) return;

    const scoreRaw   = payload.security_score;
    const topTool    = payload.top_risky_tool || "-";
    const topCwe     = payload.top_cwe || "-";
    const topModule  = payload.top_module || "-";

    // Security Score: giữ nguyên 0–100 nếu backend trả về
    const score = safeNumber(scoreRaw);

    const elScore   = $("vsp-kpi-security-score");
    const elTopTool = $("vsp-kpi-top-tool");
    const elTopCwe  = $("vsp-kpi-top-cwe");
    const elTopMod  = $("vsp-kpi-top-module");

    if (elScore) {
      // nếu anh muốn format “62.7 / 100”:
      if (Number.isFinite(score)) {
        elScore.textContent = score.toFixed(1);
      } else {
        elScore.textContent = "0.0";
      }
    }

    if (elTopTool) elTopTool.textContent  = topTool;
    if (elTopCwe)  elTopCwe.textContent   = topCwe;
    if (elTopMod)  elTopMod.textContent   = topModule;
  }

  function fetchAndRenderDashboard() {
    fetch(API_URL, {
      method: "GET",
      headers: {
        "Accept": "application/json"
      }
    })
      .then(function (res) {
        if (!res.ok) {
          throw new Error("HTTP " + res.status);
        }
        return res.json();
      })
      .then(function (data) {
        if (!data || data.ok === false) {
          console.warn("[VSP][DASH] Payload ok=false hoặc rỗng:", data);
          return;
        }

        // data chính là dashboard_v3 payload
        bindKpiCards(data);
        bindAdvancedKpi(data);

        console.log("[VSP][DASH] Dashboard_v3 bound:", {
          run_id: data.run_id,
          total_findings: data.total_findings
        });
      })
      .catch(function (err) {
        console.error("[VSP][DASH] Fetch /api/vsp/dashboard_v3 lỗi:", err);
      });
  }

  // Expose global để tab runtime / nút Refresh có thể gọi
  window.VSP_DASHBOARD_V3 = {
    refresh: fetchAndRenderDashboard
  };

  document.addEventListener("DOMContentLoaded", function () {
    // Khi dashboard tab load lần đầu → tự gọi
    fetchAndRenderDashboard();
  });
})();
