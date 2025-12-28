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
    marker = "<!-- [iso_notes_cio_force_v1] -->"
    if marker in html:
        print("[i] ISO box force đã có trong", path)
        continue

    body_idx = html.lower().find("<body")
    if body_idx == -1:
        print("[WARN] Không thấy <body trong", path, "- sẽ append cuối file.")
        insert_pos = len(html)
    else:
        gt_idx = html.find(">", body_idx)
        if gt_idx == -1:
            print("[WARN] Không thấy '>' của <body trong", path, "- sẽ append cuối file.")
            insert_pos = len(html)
        else:
            insert_pos = gt_idx + 1  # ngay sau tag <body ...>

    block = r"""
<!-- [iso_notes_cio_force_v1] -->
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

    new_html = html[:insert_pos] + block + html[insert_pos:]
    path.write_text(new_html, encoding="utf-8")
    print("[OK] ĐÃ CHÈN ISO box ngay sau <body> trong", path)

# Thêm CSS cho box nếu chưa có
css_path = Path("static/css/security_resilient.css")
if css_path.exists():
    css = css_path.read_text(encoding="utf-8")
    marker = "/* [iso_notes_cio_force_v1] */"
    if marker not in css:
        extra = r"""
/* [iso_notes_cio_force_v1] – style box ISO notes (force) */
.sb-settings-notes {
  margin: 16px;
  padding: 14px 16px;
  border-radius: 10px;
  border: 1px solid rgba(124,252,0,0.35);
  background: radial-gradient(circle at top left,
              rgba(124,252,0,0.18),
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
"""
        css = css.rstrip() + extra + "\n"
        css_path.write_text(css, encoding="utf-8")
        print("[OK] ĐÃ THÊM CSS iso_notes_cio_force_v1 vào", css_path)
    else:
        print("[i] CSS iso_notes_cio_force_v1 đã tồn tại.")
else:
    print("[WARN] Không tìm thấy static/css/security_resilient.css")
PY

echo "[DONE] patch_settings_iso_force_top.sh"
