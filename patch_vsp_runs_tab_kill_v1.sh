#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS_DIR="$ROOT/static/js"
BACKUP_DIR="$JS_DIR/backup_$(date +%Y%m%d_%H%M%S)"

echo "[PATCH] Backup JS vào $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

cp "$JS_DIR/vsp_runs_v1.js" "$BACKUP_DIR/vsp_runs_v1.js.bak" 2>/dev/null || true
cp "$JS_DIR/vsp_runs_reports_v2.js" "$BACKUP_DIR/vsp_runs_reports_v2.js.bak" 2>/dev/null || true

############################################################
# 1) STUB HOÁ vsp_runs_reports_v2.js (legacy V1) – KHÔNG log V1
############################################################
cat > "$JS_DIR/vsp_runs_reports_v2.js" << 'JS_EOF'
/*
 * VSP 2025 – Runs & Reports legacy stub
 * File này CHỈ để tránh crash từ các template cũ còn gọi loadRunsTable().
 * Tuyệt đối không dùng logic VSP_RUNS_UI_V1 nữa.
 */
const VSP_RUNS_REPORTS_LOG = "[VSP_RUNS_REPORTS_STUB]";

console.log(VSP_RUNS_REPORTS_LOG, "loaded – legacy runs-report features are disabled.");

window.loadRunsTable = function () {
  // Nếu template cũ còn gọi loadRunsTable(), chỉ log 1 dòng nhẹ rồi bỏ qua.
  console.log(VSP_RUNS_REPORTS_LOG, "loadRunsTable() called – ignoring legacy implementation.");
};
JS_EOF

############################################################
# 2) vsp_runs_v1.js – implementation mới, tự fetch runs_index_v3
############################################################
cat > "$JS_DIR/vsp_runs_v1.js" << 'JS_EOF'
/*
 * VSP 2025 – TAB 2: Runs & Reports
 * Bản clean, không dính VSP_RUNS_UI_V1.
 * Logic:
 *   - Chờ DOM ready & tồn tại #vsp-runs-tbody mới chạy.
 *   - Fetch /api/vsp/runs_index_v3.
 *   - Tự đoán schema (items / runs / array).
 *   - Render bảng run history.
 */

const VSP_RUNS_LOG = "[VSP_RUNS_TAB]";

function vspRunsWaitForDom(selector, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    function check() {
      const el = document.querySelector(selector);
      if (el) return resolve(el);
      if (Date.now() - start > timeoutMs) {
        return reject(new Error("Timeout chờ selector " + selector));
      }
      requestAnimationFrame(check);
    }
    check();
  });
}

function vspNormalizeRuns(payload) {
  if (!payload) return [];

  // Case 1: trả về array trực tiếp
  if (Array.isArray(payload)) return payload;

  // Case 2: { items: [...] }
  if (Array.isArray(payload.items)) return payload.items;

  // Case 3: { runs: [...] }
  if (Array.isArray(payload.runs)) return payload.runs;

  // Case 4: { data: [...] } hoặc { results: [...] }
  if (Array.isArray(payload.data)) return payload.data;
  if (Array.isArray(payload.results)) return payload.results;

  // Thử đoán trong các field object
  try {
    const vals = Object.values(payload).filter(
      (v) => v && typeof v === "object"
    );
    const guess = vals.find(
      (v) => Array.isArray(v) && v.length && typeof v[0] === "object"
    );
    if (guess) return guess;
  } catch (e) {
    console.warn(VSP_RUNS_LOG, "normalizeRuns() lỗi khi đoán schema:", e);
  }

  console.warn(VSP_RUNS_LOG, "normalizeRuns(): không đoán được schema, trả []");
  return [];
}

function vspSumBySeverity(bySeverity) {
  if (!bySeverity || typeof bySeverity !== "object") return 0;
  return ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"].reduce(
    (acc, k) => acc + (typeof bySeverity[k] === "number" ? bySeverity[k] : 0),
    0
  );
}

function vspRenderRunsTable(rows) {
  const tbody = document.querySelector("#vsp-runs-tbody");
  if (!tbody) {
    console.warn(VSP_RUNS_LOG, "Không tìm thấy #vsp-runs-tbody – bỏ qua render bảng.");
    return;
  }

  tbody.innerHTML = "";

  if (!rows.length) {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.colSpan = 12;
    td.textContent = "Không có RUN nào trong runs_index_v3.";
    td.style.textAlign = "center";
    td.style.opacity = "0.7";
    tr.appendChild(td);
    tbody.appendChild(tr);
    return;
  }

  rows.forEach((run, index) => {
    const tr = document.createElement("tr");

    const bySeverity = run.by_severity || run.bySeverity || {};
    const totalFindings = run.total_findings ??
      run.totalFindings ??
      vspSumBySeverity(bySeverity);

    const toolsObj = run.by_tool || run.byTool || {};
    const toolsList = Object.keys(toolsObj);
    const toolsEnabled = toolsList.length;

    const ts =
      run.ts ||
      run.timestamp ||
      run.time ||
      run.created_at ||
      "";

    const profile = run.profile || run.scan_profile || run.mode || "-";
    const srcPath = run.source_root || run.src_root || run.src_path || run.project || "-";
    const url = run.target_url || run.url || run.app || "-";

    const severities = {
      crit: bySeverity.CRITICAL || bySeverity.critical || 0,
      high: bySeverity.HIGH || bySeverity.high || 0,
      med: bySeverity.MEDIUM || bySeverity.medium || 0,
      low: bySeverity.LOW || bySeverity.low || 0,
      info: bySeverity.INFO || bySeverity.info || 0,
      trace: bySeverity.TRACE || bySeverity.trace || 0,
    };

    const cols = [
      index + 1,
      ts || "-",
      profile,
      srcPath,
      url,
      severities.crit,
      severities.high,
      severities.med,
      severities.low,
      severities.info,
      severities.trace,
      toolsList.join(", ") || "-",
    ];

    cols.forEach((val) => {
      const td = document.createElement("td");
      td.textContent = val;
      tr.appendChild(td);
    });

    tbody.appendChild(tr);
  });
}

async function vspInitRunsTab() {
  console.log(VSP_RUNS_LOG, "vsp_runs_v1.js loaded – chuẩn bị fetch runs_index_v3…");

  try {
    await vspRunsWaitForDom("#vsp-runs-tbody", 5000);
  } catch (e) {
    console.warn(VSP_RUNS_LOG, "Không tìm thấy #vsp-runs-tbody sau 5s:", e.message);
    return;
  }

  let resp;
  try {
    resp = await fetch("/api/vsp/runs_index_v3", { credentials: "same-origin" });
  } catch (e) {
    console.error(VSP_RUNS_LOG, "Fetch /api/vsp/runs_index_v3 lỗi:", e);
    return;
  }

  if (!resp.ok) {
    console.error(
      VSP_RUNS_LOG,
      "Fetch /api/vsp/runs_index_v3 HTTP",
      resp.status,
      resp.statusText
    );
    return;
  }

  let data;
  try {
    data = await resp.json();
  } catch (e) {
    console.error(VSP_RUNS_LOG, "Không parse được JSON từ runs_index_v3:", e);
    return;
  }

  console.log(VSP_RUNS_LOG, "Raw data từ runs_index_v3 =", data);

  const runs = vspNormalizeRuns(data);
  console.log(VSP_RUNS_LOG, "Loaded", runs.length, "runs từ runs_index_v3");

  vspRenderRunsTable(runs);
}

// Chạy khi DOM ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", vspInitRunsTab);
} else {
  vspInitRunsTab();
}
JS_EOF

echo "[PATCH] Đã ghi lại:"
echo "  - static/js/vsp_runs_reports_v2.js (stub, không còn VSP_RUNS_UI_V1)"
echo "  - static/js/vsp_runs_v1.js (TAB 2 mới, fetch runs_index_v3)"
echo "[PATCH] Xong. Hãy restart Flask UI (nếu cần) và hard-reload trình duyệt (Ctrl+Shift+R)."
