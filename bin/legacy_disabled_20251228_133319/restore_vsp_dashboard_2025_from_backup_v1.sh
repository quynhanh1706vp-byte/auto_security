#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL_DIR="${ROOT}/templates"
TARGET="${TPL_DIR}/vsp_dashboard_2025.html"

echo "[RESTORE] ROOT    = ${ROOT}"
echo "[RESTORE] TPL_DIR = ${TPL_DIR}"
echo "[RESTORE] TARGET  = ${TARGET}"

LATEST="$(ls -1 "${TARGET}".bak_* 2>/dev/null | sort | tail -n1 || true)"

if [ -z "${LATEST}" ]; then
  echo "[RESTORE][ERR] Không tìm thấy backup kiểu vsp_dashboard_2025.html.bak_*"
  exit 1
fi

echo "[RESTORE] Dùng backup mới nhất:"
echo "          ${LATEST}"

cp "${LATEST}" "${TARGET}"

echo "[RESTORE] Đã khôi phục ${TARGET} từ backup."
