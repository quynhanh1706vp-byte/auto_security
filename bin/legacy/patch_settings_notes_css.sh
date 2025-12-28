#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] CSS  = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text()

marker = "/* PATCH_TOOL_NOTES_STYLE */"

if marker in css:
    print("[OK] CSS đã có PATCH_TOOL_NOTES_STYLE, bỏ qua.")
else:
    snippet = """
/* PATCH_TOOL_NOTES_STYLE */
/* Textarea cho cột GHI CHÚ (Settings – tool_config) */
table textarea {
  background-color: #020617;      /* rất tối, hợp nền */
  color: #e5e7eb;                 /* chữ xám nhạt */
  border-radius: 0.75rem;         /* bo góc mềm như các ô khác */
  border: 1px solid #334155;      /* viền xám đậm */
  font-size: 12px;
  line-height: 1.4;
  padding: 6px 10px;
  width: 100%;
  max-height: 80px;               /* đủ 3–4 dòng */
  resize: vertical;
  white-space: normal;
  word-break: break-word;
}
table textarea:focus {
  outline: none;
  border-color: #38bdf8;          /* xanh focus nhẹ */
  box-shadow: 0 0 0 1px #0ea5e9;
}
"""
    css = css + "\n" + snippet + "\n"
    path.write_text(css)
    print("[OK] Đã append PATCH_TOOL_NOTES_STYLE vào CSS.")
PY

echo "[DONE] patch_settings_notes_css.sh hoàn thành."
