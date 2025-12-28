#!/usr/bin/env bash
set -euo pipefail

echo "[i] === BẮT ĐẦU patch UI: theme xanh + menu RULE overrides + ghi chú ISO Settings ==="

########################################
# 1) THEME XANH LÁ SÁNG TOÀN BỘ UI
########################################
CSS="static/css/security_resilient.css"

python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [theme_green_bright_v3] */"
if marker in css:
    print("[i] CSS: đã có theme_green_bright_v3 – không thêm lại.")
else:
    extra = """
/* [theme_green_bright_v3] – override toàn bộ theme sang xanh lá sáng */
:root {
  --sb-accent: #7CFC00;                   /* lime green sáng */
  --sb-accent-soft: rgba(124,252,0,0.18);
  --sb-accent-soft-strong: rgba(124,252,0,0.30);
}

/* Nền tổng thể (mọi trang) */
body {
  background: radial-gradient(circle at top, #122515 0%, #050a06 55%, #020405 100%) !important;
}

/* Card chung */
.sb-card, .card {
  border-color: rgba(124,252,0,0.35) !important;
  box-shadow: 0 0 18px rgba(124,252,0,0.18) !important;
  background: rgba(6, 14, 8, 0.96) !important;
}

/* Title / heading trong card & main */
.sb-card h2,
.sb-card-title,
.sb-section-title,
.sb-main-title {
  color: #e9ffe5 !important;
}

/* Sub-title / text nhấn */
.sb-main-subtitle {
  color: #c8ffd0 !important;
}

/* KPI (TOTAL, CRIT, HIGH, MEDIUM, LOW) */
.kpi-card, .kpi, .sb-kpi-card {
  border-color: rgba(124,252,0,0.35) !important;
  background: linear-gradient(135deg,
              rgba(124,252,0,0.18),
              rgba(0,0,0,0.18)) !important;
}

/* Nút chính (Run scan, Save, v.v.) */
button,
.btn,
.sb-btn,
.sb-btn-primary,
.run-btn,
.run-button {
  background: var(--sb-accent) !important;
  border-color: var(--sb-accent) !important;
  color: #021004 !important;
}

/* Sidebar nav */
.sidebar .nav-item,
.nav-item {
  border-radius: 8px;
}

.sidebar .nav-item.active,
.sidebar .nav-item.active a,
.nav-item.active,
.nav-item.active a {
  background: var(--sb-accent) !important;
  color: #021004 !important;
}

.sidebar .nav-item a,
.nav-item a {
  color: #bdfcaf !important;
}

.sidebar .nav-item a:hover,
.nav-item a:hover {
  background: var(--sb-accent-soft) !important;
}

/* Thanh progress / severity bar cũ */
.progress-bar,
.severity-bar,
.sb-mini-bar {
  background: var(--sb-accent) !important;
}

/* Link xanh */
a, a:visited {
  color: #9dff6a !important;
}
"""
    css = css.rstrip() + extra + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] CSS: đã thêm block theme_green_bright_v3 vào", path)
PY

########################################
# 2) ĐỔI TEXT MENU: 'Scan PROJECT' -> 'RULE overrides'
########################################
python3 - <<'PY'
from pathlib import Path

root = Path("templates")
count = 0
for path in root.rglob("*.html"):
    text = path.read_text(encoding="utf-8")
    new = text
    # các biến thể có thể có
    new = new.replace("Scan PROJECT", "RULE overrides")
    new = new.replace("Scan Project", "RULE overrides")
    new = new.replace("Scan project", "RULE overrides")

    if new != text:
        path.write_text(new, encoding="utf-8")
        print("[OK] MENU: patch trong", path)
        count += 1

if count == 0:
    print("[WARN] MENU: không tìm thấy 'Scan PROJECT' / 'Scan Project' trong templates – có thể đã đổi trước.")
else:
    print(f"[DONE] MENU: đã đổi text trong {count} file.")
PY

########################################
# 3) THÊM BOX GHI CHÚ ISO 27001 / DEVSECOPS TRONG SETTINGS
########################################
TPL = "templates/settings.html"

python3 - "$TPL" <<'PY'
from pathlib import Path
path = Path("templates/settings.html")
html = path.read_text(encoding="utf-8")

marker = "<!-- [settings_iso_notes_v3] -->"
if marker in html:
    print("[i] SETTINGS: đã có settings_iso_notes_v3 – không chèn lại.")
else:
    # Cố gắng thay nguyên block sb-main-header bằng header mới + ghi chú
    start = html.find('<div class="sb-main-header">')
    if start == -1:
        print("[WARN] SETTINGS: không tìm thấy '<div class=\"sb-main-header\">', sẽ append box cuối file.")
        block = """
<!-- [settings_iso_notes_v3] -->
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
    <li><b>Exception &amp; RULE overrides</b>: các rule được đánh dấu “accept risk”
        hoặc “compensating controls” được quản lý trong tab <b>RULE overrides</b>,
        phù hợp quy trình Risk Treatment của ISO 27001.</li>
    <li><b>Logging &amp; Evidence</b>: mọi cấu hình đang áp dụng được lưu lại để
        dùng làm bằng chứng audit (evidence) cho các cuộc đánh giá.</li>
  </ul>
  <p>
    Gợi ý: CIO / CISO nên khoá trước 1–2 profile chuẩn (ví dụ <b>EXT-PROD</b>, <b>FAST-DEV</b>)
    và yêu cầu các team sử dụng đúng profile này trong pipeline để đảm bảo tính nhất quán
    và tuân thủ chuẩn ISO 27001 / DevSecOps.
  </p>
</div>
"""
        html = html.rstrip() + block + "\n"
    else:
        end = html.find("</div>", start)
        if end == -1:
            print("[WARN] SETTINGS: không xác định được hết sb-main-header, fallback append cuối file.")
            block = """
<!-- [settings_iso_notes_v3] -->
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
    <li><b>Exception &amp; RULE overrides</b>: các rule được đánh dấu “accept risk”
        hoặc “compensating controls” được quản lý trong tab <b>RULE overrides</b>,
        phù hợp quy trình Risk Treatment của ISO 27001.</li>
    <li><b>Logging &amp; Evidence</b>: mọi cấu hình đang áp dụng được lưu lại để
        dùng làm bằng chứng audit (evidence) cho các cuộc đánh giá.</li>
  </ul>
  <p>
    Gợi ý: CIO / CISO nên khoá trước 1–2 profile chuẩn (ví dụ <b>EXT-PROD</b>, <b>FAST-DEV</b>)
    và yêu cầu các team sử dụng đúng profile này trong pipeline để đảm bảo tính nhất quán
    và tuân thủ chuẩn ISO 27001 / DevSecOps.
  </p>
</div>
"""
            html = html.rstrip() + block + "\n"
        else:
            end += len("</div>")
            header_block = '''  <div class="sb-main-header">
    <div class="sb-main-title">Settings</div>
    <div class="sb-main-subtitle">Tool configuration loaded from <code>tool_config.json</code>.</div>
    <div class="sb-pill-top-right">
      Config file: {{ cfg_path }}
    </div>
  </div>
<!-- [settings_iso_notes_v3] -->
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
      <li><b>Exception &amp; RULE overrides</b>: các rule được đánh dấu “accept risk”
          hoặc “compensating controls” được quản lý trong tab <b>RULE overrides</b>,
          phù hợp quy trình Risk Treatment của ISO 27001.</li>
      <li><b>Logging &amp; Evidence</b>: mọi cấu hình đang áp dụng được lưu lại để
          dùng làm bằng chứng audit (evidence) cho các cuộc đánh giá.</li>
    </ul>
    <p>
      Gợi ý: CIO / CISO nên khoá trước 1–2 profile chuẩn (ví dụ <b>EXT-PROD</b>, <b>FAST-DEV</b>)
      và yêu cầu các team sử dụng đúng profile này trong pipeline để đảm bảo tính nhất quán
      và tuân thủ chuẩn ISO 27001 / DevSecOps.
    </p>
  </div>
'''
            html = html[:start] + header_block + html[end:]

    path.write_text(html, encoding="utf-8")
    print("[OK] SETTINGS: đã chèn block settings_iso_notes_v3 vào", path)
PY

# CSS cho box ghi chú
python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [settings_iso_notes_v3] */"
if marker in css:
    print("[i] CSS: settings_iso_notes_v3 đã có.")
else:
    extra = """
/* [settings_iso_notes_v3] – box ghi chú ISO 27001 / DevSecOps (CIO) */
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
    print("[OK] CSS: đã thêm settings_iso_notes_v3 vào", path)
PY

echo "[i] === HOÀN TẤT patch_ui_green_rule_iso_v3 ==="
