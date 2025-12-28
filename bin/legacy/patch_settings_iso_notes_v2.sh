#!/usr/bin/env bash
set -euo pipefail

TPL="templates/settings.html"

echo "[i] Thêm ghi chú ISO 27001 / DevSecOps CIO vào $TPL (ngay dưới subtitle)."

python3 - "$TPL" <<'PY'
from pathlib import Path
path = Path("templates/settings.html")
html = path.read_text(encoding="utf-8")

marker = "<!-- [settings_iso_notes_v2] -->"
if marker in html:
    print("[i] Đã có block settings_iso_notes_v2, bỏ qua.")
else:
    # Tìm subtitle "Tool configuration loaded from tool_config.json"
    anchor = '<div class="sb-main-subtitle">Tool configuration loaded from <code>tool_config.json</code>.</div>'
    if anchor not in html:
        print("[WARN] Không tìm thấy anchor subtitle; sẽ append block cuối file.")
        insert_at = len(html)
        new_html = html.rstrip() + """

<!-- [settings_iso_notes_v2] -->
<div class="sb-settings-notes">
  <h3>Ghi chú cấu hình theo ISO 27001 &amp; DevSecOps (CIO view)</h3>
  <p>
    Phần <b>Tool configuration</b> cho phép CIO / CISO / DevSecOps Lead điều chỉnh
    profile quét theo chuẩn <b>ISO 27001</b> và mô hình <b>DevSecOps</b>:
  </p>
  <ul>
    <li><b>Scope &amp; Asset</b>: bật/tắt từng tool (Semgrep, Trivy, Gitleaks, v.v.)
        theo phạm vi <b>Code / Container / Infra / Secrets</b>.</li>
    <li><b>Level (Aggressive / Standard / Fast)</b>: ánh xạ với mức độ kiểm soát
        trong ISO 27001 – Aggressive dùng cho PROD / Audit, Fast dùng cho DEV.</li>
    <li><b>Mode (Offline / Online / CI/CD)</b>: lựa chọn mode phù hợp pipeline
        CI/CD, chạy định kỳ hoặc theo yêu cầu của CIO/CTO.</li>
    <li><b>Exception &amp; Rule overrides</b>: các rule được đánh dấu “accept risk”
        hoặc “compensating controls” sẽ được quản lý trong tab <b>RULE overrides</b>,
        phù hợp quy trình quản lý rủi ro (Risk Treatment) của ISO 27001.</li>
    <li><b>Logging &amp; Evidence</b>: mọi cấu hình đang áp dụng được lưu lại để
        dùng làm bằng chứng audit (evidence) cho các cuộc đánh giá nội bộ/bên thứ 3.</li>
  </ul>
  <p>
    Gợi ý: CIO / CISO nên khoá trước 1–2 profile chuẩn (ví dụ <b>EXT-PROD</b>, <b>FAST-DEV</b>)
    và yêu cầu các team sử dụng đúng profile này trong pipeline để đảm bảo tính nhất quán
    và tuân thủ chuẩn ISO 27001 / DevSecOps.
  </p>
</div>
"""
    else:
        new_block = anchor + """
<!-- [settings_iso_notes_v2] -->
<div class="sb-settings-notes">
  <h3>Ghi chú cấu hình theo ISO 27001 &amp; DevSecOps (CIO view)</h3>
  <p>
    Phần <b>Tool configuration</b> cho phép CIO / CISO / DevSecOps Lead điều chỉnh
    profile quét theo chuẩn <b>ISO 27001</b> và mô hình <b>DevSecOps</b>:
  </p>
  <ul>
    <li><b>Scope &amp; Asset</b>: bật/tắt từng tool (Semgrep, Trivy, Gitleaks, v.v.)
        theo phạm vi <b>Code / Container / Infra / Secrets</b>.</li>
    <li><b>Level (Aggressive / Standard / Fast)</b>: ánh xạ với mức độ kiểm soát
        trong ISO 27001 – Aggressive dùng cho PROD / Audit, Fast dùng cho DEV.</li>
    <li><b>Mode (Offline / Online / CI/CD)</b>: lựa chọn mode phù hợp pipeline
        CI/CD, chạy định kỳ hoặc theo yêu cầu của CIO/CTO.</li>
    <li><b>Exception &amp; Rule overrides</b>: các rule được đánh dấu “accept risk”
        hoặc “compensating controls” sẽ được quản lý trong tab <b>RULE overrides</b>,
        phù hợp quy trình quản lý rủi ro (Risk Treatment) của ISO 27001.</li>
    <li><b>Logging &amp; Evidence</b>: mọi cấu hình đang áp dụng được lưu lại để
        dùng làm bằng chứng audit (evidence) cho các cuộc đánh giá nội bộ/bên thứ 3.</li>
  </ul>
  <p>
    Gợi ý: CIO / CISO nên khoá trước 1–2 profile chuẩn (ví dụ <b>EXT-PROD</b>, <b>FAST-DEV</b>)
    và yêu cầu các team sử dụng đúng profile này trong pipeline để đảm bảo tính nhất quán
    và tuân thủ chuẩn ISO 27001 / DevSecOps.
  </p>
</div>
"""
        new_html = html.replace(anchor, new_block)

    path.write_text(new_html, encoding="utf-8")
    print("[OK] Đã chèn block settings_iso_notes_v2 vào", path)
PY

# CSS cho box ghi chú
CSS="static/css/security_resilient.css"
python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [settings_iso_notes_v2] */"
if marker in css:
    print("[i] CSS settings_iso_notes_v2 đã có.")
else:
    extra = """
/* [settings_iso_notes_v2] – box ghi chú ISO 27001 / DevSecOps (CIO) */
.sb-settings-notes {
  margin-top: 18px;
  padding: 14px 16px;
  border-radius: 10px;
  border: 1px solid rgba(124,252,0,0.35);
  background: radial-gradient(circle at top left,
              rgba(124,252,0,0.16),
              rgba(0,0,0,0.7));
  font-size: 13px;
  line-height: 1.5;
}
.sb-settings-notes h3 {
  margin-top: 0;
  margin-bottom: 8px;
  font-size: 14px;
  letter-spacing: .08em;
  text-transform: uppercase;
}
.sb-settings-notes ul {
  margin: 6px 0 8px 18px;
}
.sb-settings-notes li {
  margin-bottom: 4px;
}
"""
    css = css.rstrip() + extra + "\\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã thêm CSS settings_iso_notes_v2 vào", path)
PY

echo "[DONE] patch_settings_iso_notes_v2.sh hoàn thành."
