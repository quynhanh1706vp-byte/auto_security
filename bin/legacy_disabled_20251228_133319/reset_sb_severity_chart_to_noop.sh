#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/patch_sb_severity_chart.js"

echo "[i] ROOT = $ROOT"
echo "[i] Ghi đè $JS thành NO-OP (không động gì vào UI)."

cat > "$JS" <<'JS'
/**
 * patch_sb_severity_chart.js – NO-OP
 * Tạm thời tắt mọi chỉnh sửa SEVERITY BUCKETS để UI ổn định.
 */
document.addEventListener("DOMContentLoaded", function () {
  console.log("[SB][sev] severity chart patch disabled (NO-OP).");
});
JS

echo "[OK] Đã ghi $JS – script giờ chỉ log, không sửa DOM."
