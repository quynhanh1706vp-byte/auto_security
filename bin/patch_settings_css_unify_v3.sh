#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

cp "$CSS" "${CSS}.bak_settings_css_unify_v3_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup security_resilient.css."

python3 - << 'PY'
from pathlib import Path

path = Path("static/css/security_resilient.css")
data = path.read_text(encoding="utf-8")

marker = "/* ========== SETTINGS PAGE FINAL UNIFY V3 ========== */"
if marker in data:
    print("[INFO] Block SETTINGS PAGE FINAL UNIFY V3 đã tồn tại, bỏ qua append.")
else:
    block = f"""

{marker}
.sb-main.sb-main-settings {{
  /* giống các tab khác: nội dung ở giữa, không dính sát mép trái */
  padding: 24px 40px 40px;
  display: flex;
  justify-content: center;
  align-items: flex-start;
}}

.sb-main.sb-main-settings > * {{
  /* khung nội dung chính của Settings */
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
}}

/* Bảng BY TOOL / CONFIG – đồng bộ với các bảng summary */
.sb-table.sb-table-settings {{
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  table-layout: fixed;
}}

.sb-table.sb-table-settings thead tr {{
  background: rgba(255,255,255,0.05);
}}

.sb-table.sb-table-settings th,
.sb-table.sb-table-settings td {{
  padding: 7px 12px;
  text-align: left;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}}

.sb-table.sb-table-settings tbody tr:nth-child(even) {{
  background: rgba(255,255,255,0.015);
}}

.sb-table.sb-table-settings tbody tr:hover {{
  background: rgba(255,255,255,0.05);
}}

.sb-table.sb-table-settings th:first-child,
.sb-table.sb-table-settings td:first-child {{
  padding-left: 16px;
}}

.sb-table.sb-table-settings th:last-child,
.sb-table.sb-table-settings td:last-child {{
  padding-right: 16px;
}}
"""
    path.write_text(data.rstrip() + block + "\n", encoding="utf-8")
    print("[OK] Đã append block SETTINGS PAGE FINAL UNIFY V3 vào security_resilient.css.")
PY

echo "[DONE] patch_settings_css_unify_v3.sh hoàn thành."
