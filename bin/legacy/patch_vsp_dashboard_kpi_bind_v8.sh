#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS="$UI_ROOT/static/js/vsp_dashboard_kpi_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

backup="$JS.bak_bind_v8_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$backup"
echo "[BACKUP] $JS -> $backup"

cat > "$JS" << 'JS'
/**
 * VSP Dashboard KPI binder V8
 * - Xoá mọi overlay cũ (.vsp-kpi-overlay-number) trên trang.
 * - Chỉ bind số vào 10 card KPI (TOTAL FINDINGS, CRIT/HIGH/MED/LOW,
 *   INFO+TRACE, SCORE, TOP TOOL, TOP CWE, TOP MODULE).
 * - Nhận diện card KPI bằng caption "Last run" / "Δ vs prev" / "Noise surface" / "Weighted by".
 */
(function () {
  const LOG = "[VSP][KPI_V8]";

  function ensureStyle() {
    if (document.getElementById("vsp-kpi-overlay-style")) return;
    const style = document.createElement("style");
    style.id = "vsp-kpi-overlay-style";
    style.textContent = `
      .vsp-kpi-overlay-number {
        display: block;
        margin-top: 4px;
        font-size: 20px;
        font-weight: 600;
        letter-spacing: 0.03em;
      }
      .vsp-kpi-overlay-number--small {
        font-size: 16px;
      }
    `;
    document.head.appendChild(style);
  }

  function formatNumber(n) {
    if (typeof n !== "number") n = Number(n || 0);
    if (!isFinite(n)) return "0";
    try {
      return n.toLocaleString("en-US");
    } catch (e) {
      return String(n);
    }
  }

  // Xoá mọi overlay cũ trên toàn trang
  function cleanupOldOverlays() {
    document
      .querySelectorAll(".vsp-kpi-overlay-number")
      .forEach((el) => el.remove());
  }

  // Tìm element có text EXACT bằng label (ví dụ "CRITICAL")
  function findExactLabelNodes(upperLabel) {
    const root =
      document.querySelector("#vsp-tab-dashboard") || document.body;
    const all = root.querySelectorAll("*");
    const out = [];
    all.forEach((el) => {
      const t = (el.textContent || "").trim();
      if (!t) return;
      const u = t.toUpperCase();
      if (u === upperLabel) {
        out.push(el);
      }
    });
    return out;
  }

  // Kiểm tra container có đúng là card KPI hay không
  function isKpiCard(container) {
    if (!container) return false;
    const txt = (container.textContent || "").toUpperCase();
    // 10 card KPI đều có 1 trong các caption này
    if (txt.includes("LAST RUN")) return true;
    if (txt.includes("Δ VS PREV")) return true;
    if (txt.includes("NOISE SURFACE")) return true;
    if (txt.includes("WEIGHTED BY CRIT")) return true;
    if (txt.includes("MOST CRITICAL/HIGH")) return true;
    if (txt.includes("MOST FREQUENT CWE")) return true;
    if (txt.includes("CVE-HEAVY DEPENDENCY")) return true;
    return false;
  }

  // Từ label, tìm container card KPI tương ứng
  function getKpiCardForLabel(labelEl) {
    if (!labelEl) return null;
    let c = labelEl.closest("div");
    while (c && !isKpiCard(c)) {
      c = c.parentElement;
    }
    return isKpiCard(c) ? c : null;
  }

  function ensureOverlay(container, size) {
    if (!container) return null;
    let overlay = container.querySelector(".vsp-kpi-overlay-number");
    if (!overlay) {
      overlay = document.createElement("div");
      overlay.className = "vsp-kpi-overlay-number";
      container.appendChild(overlay);
    }
    if (size === "small") {
      overlay.classList.add("vsp-kpi-overlay-number--small");
    } else {
      overlay.classList.remove("vsp-kpi-overlay-number--small");
    }
    return overlay;
  }

  function bindLabel(labelText, valueObj, formatter, size) {
    const upper = labelText.toUpperCase();
    const labels = findExactLabelNodes(upper);
    let bound = 0;

    labels.forEach((labelEl) => {
      const card = getKpiCardForLabel(labelEl);
      if (!card) return; // không phải card KPI → bỏ qua
      const overlay = ensureOverlay(card, size);
      if (!overlay) return;
      overlay.textContent = formatter(valueObj);
      bound += 1;
    });

    console.log(LOG, "Bound", labelText, "x", bound, "->", valueObj);
  }

  function bindFromData(data) {
    if (!data || typeof data !== "object") return;
    ensureStyle();
    cleanupOldOverlays();

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
    bindLabel("TOTAL FINDINGS", total, formatNumber, "big");

    // 4 bucket CRIT/HIGH/MED/LOW
    bindLabel("CRITICAL", Number(sev.CRITICAL || 0), formatNumber, "big");
    bindLabel("HIGH", Number(sev.HIGH || 0), formatNumber, "big");
    bindLabel("MEDIUM", Number(sev.MEDIUM || 0), formatNumber, "big");
    bindLabel("LOW", Number(sev.LOW || 0), formatNumber, "big");

    // INFO + TRACE
    const infoTrace =
      Number(sev.INFO || 0) + Number(sev.TRACE || 0);
    bindLabel("INFO + TRACE", infoTrace, formatNumber, "small");

    // SECURITY POSTURE SCORE
    bindLabel(
      "SECURITY POSTURE SCORE",
      score === null ? "N/A" : score,
      (v) => (v === "N/A" ? "N/A" : v + " / 100"),
      "small"
    );

    // TOP RISKY TOOL
    bindLabel(
      "TOP RISKY TOOL",
      topTool,
      (obj) => {
        if (!obj || !obj.label) return "N/A";
        const n = obj.crit_high || obj.count || 0;
        return obj.label + " (" + n + ")";
      },
      "small"
    );

    // TOP IMPACTED CWE
    bindLabel(
      "TOP IMPACTED CWE",
      topCwe,
      (obj) => {
        if (!obj || !obj.label) return "N/A";
        const n = obj.count || 0;
        return obj.label + " (" + n + ")";
      },
      "small"
    );

    // TOP VULNERABLE MODULE
    bindLabel(
      "TOP VULNERABLE MODULE",
      topModule,
      (obj) => {
        if (!obj || !obj.label) return "N/A";
        const n = obj.count || 0;
        return obj.label + " (" + n + ")";
      },
      "small"
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

echo "[DONE] patch_vsp_dashboard_kpi_bind_v8.sh hoàn tất."
