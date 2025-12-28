#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/static/js/vsp_console_patch_v1.js"

echo "[DASH_DELTA_INLINE] ROOT   = ${ROOT}"
echo "[DASH_DELTA_INLINE] TARGET = ${TARGET}"

if [ ! -f "${TARGET}" ]; then
  echo "[DASH_DELTA_INLINE][ERR] Không tìm thấy ${TARGET}"
  exit 1
fi

BACKUP="${TARGET}.bak_dash_delta_inline_$(date +%Y%m%d_%H%M%S)"
cp "${TARGET}" "${BACKUP}"
echo "[DASH_DELTA_INLINE] Đã backup thành ${BACKUP}"

cat >> "${TARGET}" << 'JS'

// [VSP_DASH_DELTA_INLINE_v1] Hiển thị Δ Findings bên cạnh label "Charts"
(function () {
  const LOG = (...args) => console.log("[VSP_DASH_DELTA_INLINE]", ...args);

  function onReady(fn) {
    if (document.readyState === "complete" || document.readyState === "interactive") {
      fn();
    } else {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    }
  }

  async function fetchDelta() {
    try {
      const res = await fetch("/api/vsp/dashboard_delta_latest", { cache: "no-store" });
      if (!res.ok) {
        LOG("HTTP error", res.status);
        return;
      }
      const data = await res.json();
      if (!data || !data.ok || !data.current || !data.previous) {
        LOG("Không đủ dữ liệu delta", data);
        return;
      }
      injectDelta(data);
    } catch (e) {
      LOG("Exception khi gọi dashboard_delta_latest:", e);
    }
  }

  function injectDelta(data) {
    const current = data.current || {};
    const previous = data.previous || {};

    const curTot = typeof current.total_findings === "number" ? current.total_findings : null;
    const prevTot = typeof previous.total_findings === "number" ? previous.total_findings : null;

    if (curTot === null || prevTot === null) {
      LOG("Thiếu total_findings trong current/previous", { current, previous });
      return;
    }

    const diff = curTot - prevTot;
    const cls =
      diff > 0 ? "vsp-delta-up" :
      diff < 0 ? "vsp-delta-down" :
                 "vsp-delta-flat";

    const diffStr = diff > 0 ? `+${diff}` : `${diff}`;

    const root = document.querySelector("#vsp-dashboard-root") || document;
    if (!root) {
      LOG("Không tìm thấy #vsp-dashboard-root");
      return;
    }

    // Tìm node text "Charts" trong dashboard
    const labels = Array.from(root.querySelectorAll("*")).filter((el) => {
      if (el.childElementCount !== 0) return false;
      const txt = (el.textContent || "").trim();
      return txt === "Charts";
    });

    if (!labels.length) {
      LOG("Không tìm thấy label 'Charts' để chèn delta");
      return;
    }

    const chartsLabel = labels[0];
    if (chartsLabel.querySelector(".vsp-dash-delta-inline")) {
      LOG("Delta đã được chèn trước đó, bỏ qua.");
      return;
    }

    const span = document.createElement("span");
    span.className = "vsp-dash-delta-inline";
    span.innerHTML =
      '<span class="vsp-dash-delta-label"> · Δ Findings </span>' +
      `<span class="vsp-dash-delta-val ${cls}">${diffStr}</span>` +
      `<span class="vsp-dash-delta-runs"> (${curTot} vs ${prevTot})</span>`;

    chartsLabel.appendChild(span);

    LOG(
      "Injected delta:",
      diffStr,
      " (",
      curTot,
      "vs",
      prevTot,
      ") current:",
      current.run_id,
      "previous:",
      previous.run_id
    );
  }

  onReady(fetchDelta);
})();
JS

echo "[DASH_DELTA_INLINE] Đã append JS vào ${TARGET}"
