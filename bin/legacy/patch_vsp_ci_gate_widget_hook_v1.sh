#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/static/js/vsp_console_patch_v1.js"
BACKUP="${TARGET}.bak_ci_gate_widget_v1_$(date +%Y%m%d_%H%M%S)"

echo "[VSP_CI_GATE_WIDGET] ROOT   = ${ROOT}"
echo "[VSP_CI_GATE_WIDGET] TARGET = ${TARGET}"

if [ ! -f "${TARGET}" ]; then
  echo "[VSP_CI_GATE_WIDGET][ERR] Không tìm thấy ${TARGET}"
  exit 1
fi

cp "${TARGET}" "${BACKUP}"
echo "[VSP_CI_GATE_WIDGET] Đã backup thành ${BACKUP}"

python - "${TARGET}" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
txt = path.read_text(encoding="utf-8")

marker = "/* [VSP_CONSOLE_PATCH] END */"
snippet = r'''
// [VSP_CI_GATE_WIDGET] auto load CI gate widget
(function() {
  try {
    console.log("[VSP_CI_GATE_WIDGET] injecting widget script");
    var s = document.createElement("script");
    s.src = "/static/js/vsp_ci_gate_widget_v1.js";
    s.defer = true;
    document.head.appendChild(s);
  } catch (e) {
    console.error("[VSP_CI_GATE_WIDGET] failed to inject widget:", e);
  }
})();
'''

if marker in txt:
    new_txt = txt.replace(marker, snippet + "\n" + marker)
    print("[VSP_CI_GATE_WIDGET] Đã chèn hook trước marker END.")
else:
    new_txt = txt + "\n" + snippet + "\n"
    print("[VSP_CI_GATE_WIDGET] Không tìm thấy marker, đã append snippet ở cuối file.")

path.write_text(new_txt, encoding="utf-8")
PY

echo "[VSP_CI_GATE_WIDGET] Hoàn tất patch hook widget."
