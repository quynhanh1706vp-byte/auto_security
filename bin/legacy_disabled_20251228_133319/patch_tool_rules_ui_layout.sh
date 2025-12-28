#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$UI/templates/datasource.html"
CSS="$UI/static/css/security_resilient.css"

echo "[i] UI = $UI"

# 1) Chỉnh layout trong datasource.html (chỉ thêm class, không đổi ID)
python3 - <<'PY'
from pathlib import Path

tpl = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/datasource.html")
html = tpl.read_text(encoding="utf-8")
orig = html

# Thêm class tool-rules-section
html_new = html.replace(
    '<div class="sb-section" style="margin-top: 32px;">',
    '<div class="sb-section tool-rules-section" style="margin-top: 32px;">',
    1
)

# Thêm class tool-rules-card
html_new = html_new.replace(
    '<div class="sb-card">',
    '<div class="sb-card tool-rules-card">',
    1
)

# Header: thêm class tool-rules-header
html_new = html_new.replace(
    '<div class="sb-card-header sb-card-header-flex">',
    '<div class="sb-card-header sb-card-header-flex tool-rules-header">',
    1
)

# Actions: thêm class tool-rules-toolbar
html_new = html_new.replace(
    '<div class="sb-card-actions">',
    '<div class="sb-card-actions tool-rules-toolbar">',
    1
)

# Table: thêm class tool-rules-table
html_new = html_new.replace(
    '<table class="sb-table" id="tool-rules-table">',
    '<table class="sb-table tool-rules-table" id="tool-rules-table">',
    1
)

if html_new != orig:
    tpl.write_text(html_new, encoding="utf-8")
    print("[OK] Đã thêm class layout cho Tool rules.")
else:
    print("[INFO] Không thay đổi gì trong datasource.html (có thể đã patch trước).")
PY

# 2) Thêm CSS cho phần Tool rules
python3 - <<'PY'
from pathlib import Path

css_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/css/security_resilient.css")
css = css_path.read_text(encoding="utf-8")
orig = css

if "/* TOOL RULES UI */" not in css:
    css += """

/* TOOL RULES UI */
.tool-rules-section {
  margin-top: 40px;
}

.tool-rules-card {
  background: rgba(10, 18, 32, 0.95);
  border-radius: 16px;
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.03);
}

.tool-rules-header {
  align-items: flex-start;
}

.tool-rules-header .sb-card-title {
  font-size: 14px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.tool-rules-header .sb-card-subtitle {
  font-size: 12px;
  opacity: 0.75;
}

.tool-rules-toolbar {
  display: flex;
  gap: 8px;
}

.tool-rules-toolbar .sb-btn {
  padding: 4px 12px;
  font-size: 12px;
}

.tool-rules-table {
  font-size: 12px;
}

.tool-rules-table th {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  opacity: 0.8;
}

.tool-rules-table td {
  padding: 6px 8px;
}

#tool-rules-body tr:nth-child(even) {
  background-color: rgba(255, 255, 255, 0.02);
}

#tool-rules-body tr:hover {
  background-color: rgba(88, 175, 255, 0.10);
}
"""
    css_path.write_text(css, encoding="utf-8")
    print("[OK] Đã append CSS TOOL RULES UI.")
else:
    print("[INFO] CSS TOOL RULES UI đã tồn tại, không thêm nữa.")
PY

echo "[DONE] patch_tool_rules_ui_layout.sh hoàn thành."
