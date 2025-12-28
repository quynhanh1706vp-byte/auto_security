#!/usr/bin/env bash
set -euo pipefail

from pathlib import Path
import datetime

root = Path("templates")
path = root / "scan_one.html"
if not path.exists():
    print("[ERR] Không tìm thấy", path)
    raise SystemExit(1)

html = path.read_text(encoding="utf-8")
orig = html

# 1) Đổi menu: SCAN PROJECT -> RULE overrides
replacements = {
    "SCAN PROJECT": "RULE overrides",
    "Scan PROJECT": "RULE overrides",
    "Scan Project": "RULE overrides",
    "Scan project": "RULE overrides",
}
for old, new in replacements.items():
    if old in html:
        html = html.replace(old, new)

# 2) Chèn box ISO 27001 / DevSecOps vào phần SETTINGS – TOOL CONFIG
marker = "<!-- [settings_iso_notes_scan_v1] -->"
if marker not in html:
    # đoạn mô tả hiện tại (trong ảnh): bắt đầu bằng "Mỗi dòng tương ứng với 1 tool"
    anchors = [
        "Mỗi dòng tương ứng với 1 tool trong bundle.",
        "Mỗi dòng tương ứng với 1 tool",
    ]
    block = r"""
<!-- [settings_iso_notes_scan_v1] -->
<div class="sb-settings-notes sb-settings-notes-scan">
  <h3>Ghi chú cấu hình theo ISO 27001 &amp; DevSecOps (CIO view)</h3>
  <p>
    Bảng <b>Settings – Tool config</b> cho phép CIO / CISO / DevSecOps Lead
    chuẩn hoá cách chạy SECURITY_BUNDLE theo chuẩn <b>ISO 27001</b> và mô hình
    <b>DevSecOps</b>.
  </p>
  <ul>
    <li>
      <b>Enabled</b> – quyết định tool nào nằm trong scope kiểm soát
      (Application code / Container / Infra / Secrets).
    </li>
    <li>
      <b>Level (fast / standard / aggr)</b> – ánh xạ mức độ kiểm soát:
      <i>aggr</i> dùng cho PROD / Audit, <i>fast</i> cho DEV / local,
      <i>standard</i> cho môi trường chung.
    </li>
    <li>
      <b>Modes (Offline / Online / CI/CD)</b> – chọn mode phù hợp pipeline
      CI/CD hoặc các job quét định kỳ theo lịch của CIO/CTO.
    </li>
    <li>
      <b>RULE overrides</b> – các ngoại lệ, false positive và
      <i>compensating controls</i> được quản lý riêng ở tab
      <b>Rule overrides</b>, phục vụ quy trình Risk Treatment của ISO 27001.
    </li>
    <li>
      <b>Logging &amp; Evidence</b> – cấu hình &amp; kết quả quét được lưu lại
      để làm bằng chứng (evidence) cho audit ISO 27001, báo cáo CIO / Board.
    </li>
  </ul>
  <p>
    Gợi ý: nên khoá 1–2 profile chuẩn (ví dụ <b>EXT-PROD</b>, <b>FAST-DEV</b>)
    và yêu cầu các team dùng đúng profile này trong pipeline để đảm bảo tuân thủ.
  </p>
</div>
"""
    injected = False
    for anchor in anchors:
        if anchor in html:
            html = html.replace(anchor, anchor + "\n" + block)
            injected = True
            print("[OK] Đã chèn ISO notes ngay dưới mô tả Settings trong scan_one.html")
            break
    if not injected:
        # fallback: append cuối file (ít nhất vẫn thấy box)
        html = html.rstrip() + "\n" + block + "\n"
        print("[WARN] Không tìm được anchor mô tả, append ISO notes cuối scan_one.html")

# Nếu có thay đổi thì backup + ghi lại
if html != orig:
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = path.with_suffix(".html.bak_iso_menu_" + ts)
    backup.write_text(orig, encoding="utf-8")
    path.write_text(html, encoding="utf-8")
    print("[OK] Đã ghi lại", path)
    print("[OK] Backup cũ:", backup)
else:
    print("[INFO] Không có thay đổi nội dung scan_one.html")

# 3) Thêm CSS cho box nếu cần
css_path = Path("static/css/security_resilient.css")
if css_path.exists():
    css = css_path.read_text(encoding="utf-8")
    marker_css = "/* [settings_iso_notes_scan_v1] */"
    if marker_css not in css:
        extra = r"""
/* [settings_iso_notes_scan_v1] – box ISO notes cho UI SECURITY SCAN */
.sb-settings-notes-scan {
  margin-top: 12px;
  margin-bottom: 16px;
  padding: 12px 14px;
  border-radius: 10px;
  border: 1px solid rgba(124,252,0,0.35);
  background: radial-gradient(circle at top left,
              rgba(124,252,0,0.20),
              rgba(0,0,0,0.8));
  font-size: 13px;
  line-height: 1.5;
}
.sb-settings-notes-scan h3 {
  margin-top: 0;
  margin-bottom: 6px;
  font-size: 14px;
  letter-spacing: .08em;
  text-transform: uppercase;
}
"""
        css = css.rstrip() + extra + "\n"
        css_path.write_text(css, encoding="utf-8")
        print("[OK] Đã thêm CSS sb-settings-notes-scan vào", css_path)
    else:
        print("[INFO] CSS sb-settings-notes-scan đã tồn tại trong", css_path)
else:
    print("[WARN] Không tìm thấy", css_path)
