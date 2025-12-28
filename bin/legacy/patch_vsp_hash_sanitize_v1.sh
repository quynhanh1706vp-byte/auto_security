#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/static/js/vsp_console_patch_v1.js"
BACKUP="${TARGET}.bak_hash_sanitize_v1_$(date +%Y%m%d_%H%M%S)"

echo "[VSP_HASH_SANITIZE] ROOT   = ${ROOT}"
echo "[VSP_HASH_SANITIZE] TARGET = ${TARGET}"

if [ ! -f "${TARGET}" ]; then
  echo "[VSP_HASH_SANITIZE][ERR] Không tìm thấy ${TARGET}"
  exit 1
fi

cp "${TARGET}" "${BACKUP}"
echo "[VSP_HASH_SANITIZE] Đã backup thành ${BACKUP}"

python - "${TARGET}" << 'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
txt = path.read_text(encoding="utf-8")

snippet = r'''// [VSP_HASH_SANITIZE_V1] Fix invalid hash patterns like "#runs:ID" breaking querySelector
(function() {
  try {
    var h = window.location && window.location.hash;
    if (h && h.indexOf(":") !== -1) {
      var clean = h.split(":")[0];
      console.log("[VSP_HASH_SANITIZE_V1] Clean hash", h, "->", clean);
      window.location.hash = clean;
    }
  } catch (e) {
    console.error("[VSP_HASH_SANITIZE_V1] Error:", e);
  }
})();
'''

if "[VSP_HASH_SANITIZE_V1]" in txt:
    print("[VSP_HASH_SANITIZE] Đã có snippet, không chèn nữa.")
    new_txt = txt
else:
    new_txt = snippet + "\n\n" + txt
    print("[VSP_HASH_SANITIZE] Đã prepend snippet lên đầu file.")

path.write_text(new_txt, encoding="utf-8")
PY

echo "[VSP_HASH_SANITIZE] Hoàn tất patch."
