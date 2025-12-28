#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

root = Path("templates")
if not root.exists():
    print("[WARN] Không có templates/")
    raise SystemExit(0)

for path in root.glob("*settings*.html"):
    html = path.read_text(encoding="utf-8")
    marker = "<!-- [iso_notes_cio_minimal_v1] -->"
    if marker in html:
        print("[i] ISO box đã có trong", path)
        continue

    anchor = "Tool configuration loaded from <code>tool_config.json</code>."
    block = r"""
<!-- [iso_notes_cio_minimal_v1] -->
<div class="sb-settings-notes">
  <h3>Ghi chú cấu hình theo ISO 27001 &amp; DevSecOps (CIO view)</h3>
  <p>
    Phần <b>Tool configuration</b> cho phép CIO / CISO / DevSecOps Lead điều chỉnh
    profile quét theo chuẩn <b>ISO 27001</b> và mô hình <b>DevSecOps</b>.
  </p>
  <ul>
    <li><b>Scope &amp; Asset</b>: bật/tắt từng tool theo phạm vi Code / Container / Infra / Secrets.</li>
    <li><b>Level (Aggressive / Standard / Fast)</b>: ánh xạ với mức độ kiểm soát trong ISO 27001.</li>
    <li><b>Mode (Offline / Online / CI/CD)</b>: chọn mode phù hợp pipeline CI/CD / chạy định kỳ.</li>
    <li><b>Exception &amp; RULE overrides</b>: quản lý các rule “accept risk” / “compensating controls”.</li>
    <li><b>Logging &amp; Evidence</b>: giữ cấu hình làm bằng chứng audit.</li>
  </ul>
</div>
"""
    if anchor in html:
        html = html.replace(anchor, anchor + "\n" + block)
        print("[OK] SETTINGS:", path, "– chèn box ngay dưới subtitle.")
    else:
        html = html.rstrip() + "\n" + block + "\n"
        print("[OK] SETTINGS:", path, "– append box cuối file.")

    path.write_text(html, encoding="utf-8")

css_path = Path("static/css/security_resilient.css")
if css_path.exists():
    css = css_path.read_text(encoding="utf-8")
    marker = "/* [iso_notes_cio_minimal_v1] */"
    if marker not in css:
        extra = r"""
/* [iso_notes_cio_minimal_v1] – style box ISO notes */
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
"""
        css = css.rstrip() + extra + "\n"
        css_path.write_text(css, encoding="utf-8")
        print("[OK] Thêm CSS .sb-settings-notes vào", css_path)
PY

echo "[DONE] patch_settings_iso_box_minimal.sh"
