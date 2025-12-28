#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
echo "[PATCH] Root = $PWD"

python - << 'PY'
from pathlib import Path

p = Path("static/js/vsp_dashboard_live_v2.js")
if not p.is_file():
    print("[ERR] Không tìm thấy", p)
    raise SystemExit(1)

text = p.read_text(encoding="utf-8")

# 1) Thêm hằng API_TOP_CWE nếu chưa có
if "API_TOP_CWE" not in text:
    marker = "const API_RUNS_INDEX_V3"
    idx = text.find(marker)
    if idx != -1:
        line_end = text.find("\n", idx)
        if line_end == -1:
            line_end = idx + len(marker)
        insert = '\nconst API_TOP_CWE = "/api/vsp/top_cwe_v1";'
        text = text[:line_end] + insert + text[line_end:]
        print("[OK] Đã chèn const API_TOP_CWE vào gần", marker)
    else:
        print("[WARN] Không tìm thấy marker", marker, "– bỏ qua thêm API_TOP_CWE")

# 2) Thêm stub renderTopCweBar nếu chưa có
if "renderTopCweBar" not in text:
    stub = r"""

// ====================== TOP CWE – BASIC STUB =========================
// Nếu BE chưa có dữ liệu, hiển thị empty-state cho panel Top CWE.
function renderTopCweBar(root, data) {
  if (!root) return;
  const container = (root instanceof HTMLElement) ? root : document.querySelector(root);
  if (!container) return;

  container.innerHTML = "";

  // Nếu có data dạng array, hiển thị list đơn giản (placeholder)
  if (Array.isArray(data) && data.length > 0) {
    const table = document.createElement("table");
    table.className = "vsp-topcwe-table";

    const thead = document.createElement("thead");
    thead.innerHTML = "<tr><th>CWE</th><th>Count</th></tr>";
    table.appendChild(thead);

    const tbody = document.createElement("tbody");
    data.forEach(item => {
      const tr = document.createElement("tr");
      const cwe = (item.cwe || item.id || "CWE-?");
      const count = (item.count != null ? item.count : item.value != null ? item.value : "-");
      tr.innerHTML = "<td>" + cwe + "</td><td>" + count + "</td>";
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);

    container.appendChild(table);
    return;
  }

  // Nếu không có data -> empty state để không bị panel trống
  const empty = document.createElement("div");
  empty.className = "vsp-empty-state";
  empty.textContent = "No CWE insights for this run yet.";
  container.appendChild(empty);
}
"""
    text = text + stub
    print("[OK] Đã append stub renderTopCweBar vào cuối file.")

p.write_text(text, encoding="utf-8")
print("[DONE] Updated", p)
PY
