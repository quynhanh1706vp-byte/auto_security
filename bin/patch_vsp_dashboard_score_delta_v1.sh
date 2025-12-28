#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/static/js/vsp_console_patch_v1.js"

echo "[VSP_KPI_SCORE_DELTA] ROOT   = ${ROOT}"
echo "[VSP_KPI_SCORE_DELTA] TARGET = ${TARGET}"

if [ ! -f "${TARGET}" ]; then
  echo "[VSP_KPI_SCORE_DELTA][ERR] Không tìm thấy ${TARGET}"
  exit 1
fi

BACKUP="${TARGET}.bak_kpi_score_delta_$(date +%Y%m%d_%H%M%S)"
cp "${TARGET}" "${BACKUP}"
echo "[VSP_KPI_SCORE_DELTA] Đã backup thành ${BACKUP}"

cat >> "${TARGET}" << 'JS'

// [VSP_KPI_SCORE_DELTA_v1] Hiển thị Δ Security Score trong card KPI
(function () {
  const LOG = (...args) => console.log("[VSP_KPI_SCORE_DELTA]", ...args);

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
      renderScoreDelta(data);
    } catch (e) {
      LOG("Exception khi gọi dashboard_delta_latest:", e);
    }
  }

  function renderScoreDelta(data) {
    const current = data.current || {};
    const previous = data.previous || {};

    const curScore = Number(
      typeof current.security_posture_score === "number"
        ? current.security_posture_score
        : 0
    );
    const prevScore = Number(
      typeof previous.security_posture_score === "number"
        ? previous.security_posture_score
        : 0
    );

    if (Number.isNaN(curScore) || Number.isNaN(prevScore)) {
      LOG("Score không hợp lệ", { curScore, prevScore });
      return;
    }

    const delta = curScore - prevScore;
    const deltaStr = delta > 0 ? `+${delta}` : `${delta}`;

    let cls = "vsp-kpi-delta-flat";
    if (delta > 0) cls = "vsp-kpi-delta-up";
    else if (delta < 0) cls = "vsp-kpi-delta-down";

    const card = document.getElementById("vsp-kpi-security-score");
    if (!card) {
      LOG("Không tìm thấy card #vsp-kpi-security-score");
      return;
    }

    if (card.querySelector(".vsp-kpi-delta-score")) {
      LOG("Score delta đã tồn tại, bỏ qua.");
      return;
    }

    const div = document.createElement("div");
    div.className = `vsp-kpi-delta-score ${cls}`;
    div.textContent = `Δ Score ${deltaStr} (${prevScore} → ${curScore})`;

    card.appendChild(div);

    LOG("Render Δ Score:", {
      delta,
      curScore,
      prevScore,
      run_current: current.run_id,
      run_previous: previous.run_id,
    });
  }

  onReady(fetchDelta);
})();
JS

echo "[VSP_KPI_SCORE_DELTA] Đã append JS vào ${TARGET}"
