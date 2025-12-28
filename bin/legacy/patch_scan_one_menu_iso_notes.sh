#!/usr/bin/env bash
set -euo pipefail

TPL="templates/scan_one.html"

if [ ! -f "\$TPL" ]; then
  echo "[ERROR] Không tìm thấy template: \$TPL"
  exit 1
fi

# Backup
cp "\$TPL" "\${TPL}.bak_$(date +%Y%m%d_%H%M%S)"

# 1) Đổi menu
sed -i 's/SCAN PROJECT/RULE overrides/g' "\$TPL"
sed -i 's/Scan PROJECT/RULE overrides/g' "\$TPL"
sed -i 's/Scan Project/RULE overrides/g' "\$TPL"

echo "[INFO] Đã đổi menu SCAN PROJECT -> RULE overrides"

# 2) Thêm box ghi chú ISO ngay dưới đoạn “Mỗi dòng tương ứng với 1 tool…”
awk '
  /Mỗi dòng tương ứng với 1 tool/ && !seen {
    print
    print "<!-- [iso_notes_for_scan_one_v1] -->"
    print "<div class=\"sb-settings-notes-scan\">"
    print "<h3>Ghi chú cấu hình theo ISO 27001 &amp; DevSecOps (CIO view)</h3>"
    print "<p>Phần <b>Tool configuration</b> cho phép CIO / CISO / DevSecOps Lead chuẩn hoá cách chạy SECURITY_BUNDLE theo chuẩn <b>ISO 27001</b> và mô hình <b>DevSecOps</b>.</p>"
    print "<ul>"
    print "<li><b>Scope &amp; Asset</b>: bật/tắt tool theo phạm vi Application / Container / Infra / Secrets.</li>"
    print "<li><b>Level (Aggressive / Standard / Fast)</b>: ánh xạ mức độ kiểm soát – Aggressive cho PROD/Audit, Fast cho DEV/local.</li>"
    print "<li><b>Mode (Offline / Online / CI/CD)</b>: chọn mode phù hợp pipeline CI/CD hoặc chạy định kỳ.</li>"
    print "<li><b>Exception &amp; RULE overrides</b>: quản lý ngoại lệ / false-positive / compensating controls ở tab <b>Rule overrides</b>.</li>"
    print "<li><b>Logging &amp; Evidence</b>: lưu cấu hình & kết quả làm bằng chứng (evidence) cho audit ISO 27001.</li>"
    print "</ul>"
    print "<p>Gợi ý: CIO / CISO nên khoá 1–2 profile chuẩn (ví dụ <b>EXT-PROD</b>, <b>FAST-DEV</b>) và yêu cầu team dùng đúng profile.</p>"
    print "</div>"
    seen=1
    next
  }
  { print }
' "\$TPL" > "\$TPL.tmp" && mv "\$TPL.tmp" "\$TPL"

echo "[INFO] Đã chèn box ghi chú ISO vào \$TPL"

echo "[DONE] patch_scan_one_menu_iso_notes.sh hoàn tất"
