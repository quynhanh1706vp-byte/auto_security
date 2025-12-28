(function () {
  const API_URL = "/api/vsp/dashboard_v3";

  function $(id) {
    return document.getElementById(id);
  }

  function toNum(v) {
    v = Number(v);
    return Number.isFinite(v) ? v : 0;
  }

  function fmt(v) {
    return toNum(v).toLocaleString("en-US");
  }

  function render(payload) {
    if (!payload) return;

    var sev = payload.by_severity || {};

    var total = toNum(payload.total_findings);
    var crit  = toNum(sev.CRITICAL);
    var high  = toNum(sev.HIGH);
    var med   = toNum(sev.MEDIUM);
    var low   = toNum(sev.LOW);
    var info  = toNum(sev.INFO);
    var trace = toNum(sev.TRACE);

    if ($("vsp-kpi-total"))    $("vsp-kpi-total").textContent    = fmt(total);
    if ($("vsp-kpi-critical")) $("vsp-kpi-critical").textContent = fmt(crit);
    if ($("vsp-kpi-high"))     $("vsp-kpi-high").textContent     = fmt(high);
    if ($("vsp-kpi-medium"))   $("vsp-kpi-medium").textContent   = fmt(med);
    if ($("vsp-kpi-low"))      $("vsp-kpi-low").textContent      = fmt(low);
    if ($("vsp-kpi-info"))     $("vsp-kpi-info").textContent     = fmt(info);
    if ($("vsp-kpi-trace"))    $("vsp-kpi-trace").textContent    = fmt(trace);

    var score = toNum(payload.security_score);
    if ($("vsp-kpi-security-score")) {
      $("vsp-kpi-security-score").textContent = score.toFixed(1);
    }

    if ($("vsp-kpi-top-tool")) {
      $("vsp-kpi-top-tool").textContent = payload.top_risky_tool || "-";
    }
    if ($("vsp-kpi-top-cwe")) {
      $("vsp-kpi-top-cwe").textContent = payload.top_cwe || "-";
    }
    if ($("vsp-kpi-top-module")) {
      $("vsp-kpi-top-module").textContent = payload.top_module || "-";
    }
  }

  function init() {
    fetch(API_URL, { headers: { "Accept": "application/json" } })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (!data || data.ok === false) {
          console.warn("[VSP][FIX] dashboard_v3 ok=false:", data);
          return;
        }
        render(data);
        console.log("[VSP][FIX] dashboard_v3 bound:", {
          run_id: data.run_id,
          total_findings: data.total_findings
        });
      })
      .catch(function (err) {
        console.error("[VSP][FIX] error:", err);
      });
  }

  document.addEventListener("DOMContentLoaded", init);
})();
