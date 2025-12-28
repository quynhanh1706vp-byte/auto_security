#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"

echo "[i] UI = $UI"

########################################
# 1) Tạo template tool_rules.html (UI dark, giống các tab khác)
########################################
python3 - <<'PY'
from pathlib import Path

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
tpl = root / "templates" / "tool_rules.html"

html = """{% extends "base.html" %}

{% block content %}
  <div class="sb-main">
    <div class="sb-main-header">
      <div class="sb-main-title">Rule overrides</div>
      <div class="sb-main-subtitle">
        Quản lý rule cho từng tool: downgrade severity, bỏ qua false positive, thêm ghi chú.
        Dữ liệu được lưu vào <code>tool_rules.json</code> ở thư mục ROOT.
      </div>
    </div>

    <div class="sb-section tool-rules-section" style="margin-top: 24px;">
      <div class="sb-card">
        <div class="sb-card-header">
          <div>
            <div class="sb-card-title">Danh sách rule theo tool</div>
            <div class="sb-card-subtitle" id="tool-rules-path">
              Rules file: <code>tool_rules.json</code>
            </div>
          </div>
          <div class="sb-card-actions">
            <button id="btn-add-rule" type="button" class="sb-btn sb-btn-secondary sb-btn-sm">
              + Add rule
            </button>
            <button id="btn-reload-rules" type="button" class="sb-btn sb-btn-ghost sb-btn-sm">
              Reload
            </button>
            <button id="btn-save-rules" type="button" class="sb-btn sb-btn-primary sb-btn-sm">
              Save
            </button>
          </div>
        </div>

        <div class="sb-card-body">
          <div class="sb-table-wrapper">
            <table id="tool-rules-table" class="sb-table sb-table-sm">
              <thead>
                <tr>
                  <th style="width: 120px;">Tool</th>
                  <th>Rule ID / Pattern</th>
                  <th style="width: 130px;">Action</th>
                  <th style="width: 130px;">New severity</th>
                  <th style="width: 90px;">Enabled</th>
                  <th>Note</th>
                  <th style="width: 40px;"></th>
                </tr>
              </thead>
              <tbody id="tool-rules-body">
                <!-- Filled by datasource_tool_rules.js -->
              </tbody>
            </table>
          </div>

          <div class="sb-hint-list" style="margin-top: 16px;">
            <div class="sb-hint-title">Gợi ý:</div>
            <ul class="sb-hint-items">
              <li><b>Tool</b>: tên tool (vd semgrep, bandit, trivy-fs, gitleaks, codeql,…).</li>
              <li><b>Rule ID / Pattern</b>: mã hoặc pattern dạng chuỗi để match với id, code, hoặc substring trong message.</li>
              <li><b>Action</b>: <code>ignore</code>, <code>downgrade</code>, <code>upgrade</code>, <code>tag</code>.</li>
              <li><b>New severity</b>: <code>critical</code> / <code>high</code> / <code>medium</code> / <code>low</code> / <code>info</code>.</li>
              <li><b>Enabled</b>: bật/tắt tạm thời rule mà không cần xoá khỏi file.</li>
            </ul>
          </div>
        </div>
      </div>
    </div>

  </div>
{% endblock %}

{% block extra_js %}
  {{ super() }}
  <script src="{{ url_for('static', filename='js/datasource_tool_rules.js') }}?v=20251125"></script>
{% endblock %}
"""

tpl.write_text(html, encoding="utf-8")
print("[OK] Đã ghi templates/tool_rules.html (UI dark).")
PY

########################################
# 2) Route /tool_rules -> render tool_rules.html
########################################
python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

new_block = '''
@app.route("/tool_rules", methods=["GET"])
def tool_rules_redirect():
    from flask import render_template
    return render_template("tool_rules.html", active_page="tool_rules")
'''

if '@app.route("/tool_rules", methods=["GET"])' in text:
    text = re.sub(
        r'@app\.route\("/tool_rules", methods=\["GET"\]\)[\s\S]*?(?=\n@app\.route|\nif __name__ ==|$)',
        new_block + "\\n",
        text,
        count=1,
    )
    print("[OK] Đã thay body route /tool_rules thành render tool_rules.html.")
else:
    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if m:
        pos = m.start()
        text = text[:pos] + "\\n" + new_block + "\\n" + text[pos:]
        print("[OK] Đã chèn route /tool_rules trước main block.")
    else:
        text = text.rstrip() + "\\n" + new_block + "\\n"
        print("[WARN] Không thấy main block, append /tool_rules ở cuối file.")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

# 3) Check syntax
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_ui_xin.sh hoàn thành."
