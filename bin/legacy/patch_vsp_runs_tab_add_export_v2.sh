#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
JS="$ROOT/ui/static/js/vsp_runs_tab_v1.js"

echo "[PATCH] Target JS = $JS"

if [[ ! -f "$JS" ]]; then
  echo "[ERR] Không tìm thấy $JS" >&2
  exit 1
fi

BACKUP="${JS}.bak_export_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[PATCH] Backup: $BACKUP"

python - << 'PY'
from pathlib import Path
import re, sys

root = Path("/home/test/Data/SECURITY_BUNDLE")
js_path = root / "ui" / "static" / "js" / "vsp_runs_tab_v1.js"

txt = js_path.read_text(encoding="utf-8")

# Đã patch rồi thì bỏ qua
if "vspAttachRunExportButtons" in txt:
    print("[PATCH] Đã có vspAttachRunExportButtons trong file, bỏ qua.")
    sys.exit(0)

m = re.search(r"(['\"])use strict\1;", txt)
if not m:
    print("[ERR] Không tìm thấy 'use strict' anchor trong JS", file=sys.stderr)
    sys.exit(1)

injection = r"""
// === VSP RUN EXPORT v1 ===
if (!window.VSP_RUN_EXPORT_BASE) {
  window.VSP_RUN_EXPORT_BASE = "/api/vsp/run_export_v3";
}

window.vspExportRun = function(runId, fmt) {
  const url = `${window.VSP_RUN_EXPORT_BASE}?run_id=${encodeURIComponent(runId)}&fmt=${encodeURIComponent(fmt)}`;
  console.log("[VSP_RUN_EXPORT]", fmt, runId, "->", url);
  window.open(url, "_blank");
};

window.vspAttachRunExportButtons = function() {
  const tbody = document.getElementById("vsp-runs-tbody");
  if (!tbody) {
    console.warn("[VSP_RUN_EXPORT] tbody#vsp-runs-tbody không tìm thấy");
    return;
  }
  const rows = tbody.querySelectorAll("tr[data-run-id]");
  rows.forEach(row => {
    let cell = row.querySelector("td.vsp-run-export-cell");
    if (!cell) {
      cell = row.insertCell(-1);
      cell.className = "vsp-run-export-cell";
    } else if (cell.dataset.vspExportAttached === "1") {
      return;
    }

    const runId = row.getAttribute("data-run-id");
    if (!runId) {
      console.warn("[VSP_RUN_EXPORT] thiếu data-run-id trên row", row);
      return;
    }

    const formats = ["html", "zip", "pdf"];
    const labels = { html: "HTML", zip: "ZIP", pdf: "PDF" };

    formats.forEach(fmt => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "vsp-btn vsp-btn-xs vsp-btn-secondary";
      btn.textContent = labels[fmt];
      btn.addEventListener("click", () => window.vspExportRun(runId, fmt));
      cell.appendChild(btn);
      if (fmt !== "pdf") {
        cell.appendChild(document.createTextNode(" "));
      }
    });

    cell.dataset.vspExportAttached = "1";
  });
};
// === END VSP RUN EXPORT v1 ===
"""

new_txt = txt[:m.end()] + injection + txt[m.end():]

# Hook sau khi render table
pattern = r"(function\s+loadRunsTable\s*\(\s*runs\s*\)\s*\{)(.*?)\n\}"
m2 = re.search(pattern, new_txt, flags=re.DOTALL)
if m2:
    body = m2.group(2)
    if "vspAttachRunExportButtons" not in body:
        body = body + "\n  window.vspAttachRunExportButtons();"
        new_txt = new_txt[:m2.start(2)] + body + new_txt[m2.end(2):]
        print("[PATCH] Đã chèn vspAttachRunExportButtons() vào loadRunsTable(runs)")
else:
    print("[WARN] Không tìm thấy loadRunsTable(runs), cần gọi vspAttachRunExportButtons() tay nếu cần")

js_path.write_text(new_txt, encoding="utf-8")
print("[PATCH] Ghi file JS xong.")
PY
