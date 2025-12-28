#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/static/js/vsp_console_patch_v1.js"
BACKUP="${TARGET}.bak_dash_enhance_v1_$(date +%Y%m%d_%H%M%S)"

echo "[VSP_DASH_ENHANCE_HOOK] ROOT   = ${ROOT}"
echo "[VSP_DASH_ENHANCE_HOOK] TARGET = ${TARGET}"

if [ ! -f "${TARGET}" ]; then
  echo "[VSP_DASH_ENHANCE_HOOK][ERR] Không tìm thấy ${TARGET}"
  exit 1
fi

cp "${TARGET}" "${BACKUP}"
echo "[VSP_DASH_ENHANCE_HOOK] Đã backup thành ${BACKUP}"

python - "${TARGET}" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
txt = path.read_text(encoding="utf-8")

snippet = r'''
// [VSP_DASH_ENHANCE] load dashboard enhancement script
(function() {
  try {
    console.log("[VSP_DASH_ENHANCE] injecting script");
    var s = document.createElement("script");
    s.src = "/static/js/vsp_dashboard_enhance_v1.js";
    s.defer = true;
    document.head.appendChild(s);
  } catch (e) {
    console.error("[VSP_DASH_ENHANCE] failed to inject:", e);
  }
})();
'''

marker = "/* [VSP_CONSOLE_PATCH] END */"
if marker in txt:
    new_txt = txt.replace(marker, snippet + "\n" + marker)
    print("[VSP_DASH_ENHANCE_HOOK] Đã chèn snippet trước marker END.")
else:
    new_txt = txt + "\n" + snippet + "\n"
    print("[VSP_DASH_ENHANCE_HOOK] Không thấy marker, đã append ở cuối file.")

path.write_text(new_txt, encoding="utf-8")
PY

echo "[VSP_DASH_ENHANCE_HOOK] Hoàn tất patch."
