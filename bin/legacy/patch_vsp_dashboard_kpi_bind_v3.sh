#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS="$UI_ROOT/static/js/vsp_dashboard_kpi_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

backup="$JS.bak_bind_v3_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$backup"
echo "[BACKUP] $JS -> $backup"

cat > "$JS" << 'JS'
/**
 * VSP Dashboard KPI binder V3
 * – Không phụ thuộc class cụ thể của HTML.
 * – Tìm label theo text ("TOTAL FINDINGS", "CRITICAL", ...) rồi
 *   tìm ô value gần đó (thường đang là "-") và gán số.
 */
(function () {
  const LOG = "[VSP][KPI_V3]";

  function formatNumber(n) {
    if (typeof n !== "number") n = Number(n || 0);
    if (!isFinite(n)) return "0";
    try {
      return n.toLocaleString("en-US");
    } catch (e) {
      return String(n);
    }
  }

  function isNode(el) {
    return el && typeof el === "object" && "nodeType" in el;
  }

  function findAllLabelNodes() {
    // Giới hạn trong tab dashboard cho nhẹ
    const root =
      document.querySelector("#vsp-tab-dashboard") || document.body;
    return Array.from(root.querySelectorAll("*")).filter((el) => {
      if (!el.childNodes || el.childNodes.length === 0) return false;
      // chỉ lấy node text đơn giản
      if (el.children && el.children.length > 0) return false;
      const t = (el.textContent || "").trim();
      if (!t) return false;
      // Bỏ các text nhỏ như Δ vs prev, mô tả dưới card
      if (t.startsWith("Δ vs")) return false;
      if (t.toUpperCase().includes("NOISE SURFACE")) return false;
      if (t.toUpperCase().includes("WEIGHTED BY")) return false;
      return true;
    });
  }

  function findValueNearLabel(labelEl) {
    if (!isNode(labelEl)) return null;

    // Ưu tiên card bao ngoài
    let container =
      labelEl.closest(".vsp-kpi-card") ||
      labelEl.closest(".vsp-kpi") ||
      labelEl.parentElement;
    if (!container) container = labelEl.parentElement;

    if (!container) return null;

    // Tìm trong card những element text đang là "-" hoặc số
    const cands = Array.from(
      container.querySelectorAll("span,div,p,strong")
    );

    const cleanedLabel = (labelEl.textContent || "").trim();

    // Loại label & các text mô tả
    const good = cands.filter((el) => {
      if (el === labelEl) return false;
      const t = (el.textContent || "").trim();
      if (!t) return false;
      if (t === cleanedLabel) return false;
      if (t.startsWith("Δ vs")) return false;
      if (t.toUpperCase().includes("NOISE SURFACE")) return false;
      if (t.toUpperCase().includes("WEIGHTED BY")) return false;
      // '-' hoặc số / '0 / 100' đều coi là candidate
      if (t === "-") return true;
      if (/^\d[\d,\s/]*$/.test(t)) return true;
      return false;
    });

    if (good.length > 0) return good[0];
    return null;
  }

  function bindLabel(labelMatch, valueText, formatter) {
    const labels = findAllLabelNodes();
    const upperMatch = labelMatch.toUpperCase();
    let bound = 0;

    labels.forEach((el) => {
      const t = (el.textContent || "").trim().toUpperCase();
      if (t.startsWith(upperMatch)) {
        const valEl = findValueNearLabel(el);
        if (!valEl) return;
        const txt = formatter(valueText);
        valEl.textContent = txt;
        bound += 1;
      }
    });

    console.log(LOG, "Bound", labelMatch, "x", bound, "->", valueText);
  }

  function bindFromData(data) {
    if (!data || typeof data !== "object") return;

    const sev = data.severity_cards || {};
    const total = Number(data.total_findings || 0);
    const score =
      typeof data.security_posture_score === "number"
        ? data.security_posture_score
        : null;

    const topTool = data.top_risky_tool || null;
    const topCwe = data.top_impacted_cwe || null;
    const topModule = data.top_vulnerable_module || null;

    // TOTAL FINDINGS
    bindLabel("TOTAL FINDINGS", total, formatNumber);

    // 6 bucket severity
    bindLabel("CRITICAL", Number(sev.CRITICAL || 0), formatNumber);
    bindLabel("HIGH", Number(sev.HIGH || 0), formatNumber);
    bindLabel("MEDIUM", Number(sev.MEDIUM || 0), formatNumber);
    bindLabel("LOW", Number(sev.LOW || 0), formatNumber);

    // INFO + TRACE
    const infoTrace =
      Number(sev.INFO || 0) + Number(sev.TRACE || 0);
    bindLabel("INFO + TRACE", infoTrace, formatNumber);

    // SECURITY POSTURE SCORE
    bindLabel(
      "SECURITY POSTURE SCORE",
      score === null ? "N/A" : score,
      (v) => (v === "N/A" ? "N/A" : v + " / 100")
    );

    // TOP RISKY TOOL
    bindLabel(
      "TOP RISKY TOOL",
      topTool,
      (obj) => {
        if (!obj || !obj.label) return "N/A";
        const n = obj.crit_high || obj.count || 0;
        return obj.label + " (" + n + ")";
      }
    );

    // TOP IMPACTED CWE
    bindLabel(
      "TOP IMPACTED CWE",
      topCwe,
      (obj) => {
        if (!obj || !obj.label) return "N/A";
        const n = obj.count || 0;
        return obj.label + " (" + n + ")";
      }
    );

    // TOP VULNERABLE MODULE
    bindLabel(
      "TOP VULNERABLE MODULE",
      topModule,
      (obj) => {
        if (!obj || !obj.label) return "N/A";
        const n = obj.count || 0;
        return obj.label + " (" + n + ")";
      }
    );
  }

  async function loadDashboardKpi() {
    try {
      const res = await fetch("/api/vsp/dashboard_v3");
      if (!res.ok) {
        console.error(LOG, "HTTP", res.status);
        return;
      }
      const data = await res.json();
      console.log(LOG, "Dashboard data:", data);
      bindFromData(data);
    } catch (err) {
      console.error(LOG, "Error loading dashboard KPI:", err);
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    loadDashboardKpi();
  });

  window.vspReloadDashboardKPI = loadDashboardKpi;
})();
JS

echo "[DONE] patch_vsp_dashboard_kpi_bind_v3.sh hoàn tất."
