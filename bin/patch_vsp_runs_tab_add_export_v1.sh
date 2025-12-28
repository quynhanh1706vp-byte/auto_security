#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

JS=""
if [ -f "$ROOT/static/js/vsp_runs_tab_v1.js" ]; then
  JS="$ROOT/static/js/vsp_runs_tab_v1.js"
elif [ -f "$ROOT/static/js/vsp_runs_v1.js" ]; then
  JS="$ROOT/static/js/vsp_runs_v1.js"
else
  echo "[ERR] Không tìm thấy vsp_runs_tab_v1.js hoặc vsp_runs_v1.js trong static/js/"
  exit 1
fi

echo "[PATCH] Target JS = $JS"

BACKUP="${JS}.bak_export_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[PATCH] Backup: $BACKUP"

python - "$JS" << 'PY'
import sys, textwrap, pathlib, re

path = pathlib.Path(sys.argv[1])
txt = path.read_text(encoding="utf-8")

helpers = textwrap.dedent("""
    // VSP_RUNS_EXPORT_HELPERS_V1_BEGIN
    const VSP_RUN_EXPORT_BASE = "/api/vsp/run_export_v3";

    function vspExportRun(runId, fmt) {
      const url = VSP_RUN_EXPORT_BASE
        + "?run_id=" + encodeURIComponent(runId)
        + "&fmt=" + encodeURIComponent(fmt);
      window.open(url, "_blank");
    }

    function vspAttachRunExportButtons() {
      const tbody = document.getElementById("vsp-runs-tbody");
      if (!tbody) return;
      const rows = Array.from(tbody.querySelectorAll("tr"));
      rows.forEach((row) => {
        // tránh gắn lại nhiều lần
        if (row.querySelector(".vsp-run-export-html")) {
          return;
        }
        const firstCell = row.querySelector("td");
        if (!firstCell) return;
        const runId = (firstCell.textContent || "").trim();
        if (!runId) return;

        row.dataset.runId = runId;

        const td = document.createElement("td");
        td.innerHTML = ''
          + '<button class="vsp-run-export-html">HTML</button>'
          + '<button class="vsp-run-export-zip">ZIP</button>'
          + '<button class="vsp-run-export-pdf">PDF</button>';

        const btnHtml = td.querySelector(".vsp-run-export-html");
        const btnZip  = td.querySelector(".vsp-run-export-zip");
        const btnPdf  = td.querySelector(".vsp-run-export-pdf");

        if (btnHtml) btnHtml.addEventListener("click", () => vspExportRun(runId, "html"));
        if (btnZip)  btnZip.addEventListener("click", () => vspExportRun(runId, "zip"));
        if (btnPdf)  btnPdf.addEventListener("click", () => vspExportRun(runId, "pdf"));

        row.appendChild(td);
      });
    }
    // VSP_RUNS_EXPORT_HELPERS_V1_END

""")

# 1) Thêm helpers nếu chưa có
if "VSP_RUNS_EXPORT_HELPERS_V1_BEGIN" not in txt:
    m = re.search(r"['\"]use strict['\"];", txt)
    if m:
        idx = m.end()
        txt = txt[:idx] + "\n\n" + helpers + txt[idx:]
    else:
        txt = helpers + "\n" + txt
    print("[PY] Đã chèn block helpers export.")
else:
    print("[PY] Block helpers export đã tồn tại, bỏ qua.")

# 2) Thêm vspAttachRunExportButtons() sau lần gọi loadRuns() đầu tiên
if "vspAttachRunExportButtons()" not in txt:
    pattern = r"(loadRuns\s*\(\s*\);\s*)"
    repl = r"\1\n  vspAttachRunExportButtons();\n"
    new_txt, n = re.subn(pattern, repl, txt, count=1)
    if n == 0:
        print("[PY][WARN] Không tìm thấy 'loadRuns();' để chèn vspAttachRunExportButtons(); — bạn kiểm tra tay nhé.")
    else:
        print("[PY] Đã chèn vspAttachRunExportButtons() sau loadRuns().")
        txt = new_txt
else:
    print("[PY] Đã có vspAttachRunExportButtons() trong file, bỏ qua bước chèn.")

path.write_text(txt, encoding="utf-8")
print("[PY] DONE patch", path)
PY

chmod +x bin/patch_vsp_runs_tab_add_export_v1.sh
echo "[PATCH] Hoàn tất. Chạy: bin/patch_vsp_runs_tab_add_export_v1.sh"
