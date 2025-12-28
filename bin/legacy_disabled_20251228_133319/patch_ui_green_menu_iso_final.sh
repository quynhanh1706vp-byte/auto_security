#!/usr/bin/env bash
set -euo pipefail

echo "[i] === BẮT ĐẦU patch: THEME XANH + MENU RULE overrides + GHI CHÚ ISO SETTINGS ==="

########################################
# 1) THEME XANH LÁ SÁNG CHO TOÀN BỘ CSS
########################################
python3 - <<'PY'
from pathlib import Path

css_root = Path("static/css")
files = list(css_root.glob("*.css"))
if not files:
    print("[WARN] Không tìm thấy static/css/*.css")
for path in files:
    css = path.read_text(encoding="utf-8")
    marker = "/* [theme_green_global_v1] */"
    if marker in css:
        print(f"[i] {path}: đã có theme_green_global_v1, bỏ qua.")
        continue
    extra = r"""
/* [theme_green_global_v1] – override theme sang xanh lá sáng (global) */
:root {
  --sb-accent: #7CFC00;
  --sb-accent-soft: rgba(124,252,0,0.18);
  --sb-accent-soft-strong: rgba(124,252,0,0.30);
}

/* Nền tổng thể */
body {
  background: radial-gradient(circle at top, #122515 0%, #050a06 55%, #020405 100%) !important;
}

/* Card / panel */
.sb-card,
.card,
.panel,
.box {
  border-color: rgba(124,252,0,0.35) !important;
  box-shadow: 0 0 18px rgba(124,252,0,0.18) !important;
}

/* Headings chính */
.sb-card h2,
.sb-card-title,
.sb-section-title,
.sb-main-title,
h1, h2.section-title {
  color: #e9ffe5 !important;
}

/* KPI / widget nhỏ */
.kpi-card,
.kpi,
.sb-kpi-card {
  border-color: rgba(124,252,0,0.35) !important;
  background: linear-gradient(135deg,
              rgba(124,252,0,0.18),
              rgba(0,0,0,0.18)) !important;
}

/* Nút hành động */
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

/* Progress / severity bar */
.progress-bar,
.severity-bar,
.sb-mini-bar {
  background: var(--sb-accent) !important;
}

/* Link */
a, a:visited {
  color: #9dff6a !important;
}
"""
    css = css.rstrip() + extra + "\n"
    path.write_text(css, encoding="utf-8")
    print(f"[OK] THEME: đã thêm theme_green_global_v1 vào {path}")
PY

########################################
# 2) ĐỔI TEXT MENU: 'SCAN PROJECT' -> 'RULE overrides'
########################################
python3 - <<'PY'
from pathlib import Path

changed = 0
for root in [Path("templates"), Path("static")]:
    if not root.exists():
        continue
    for path in root.rglob("*.html"):
        txt = path.read_text(encoding="utf-8")
        new = txt.replace("SCAN PROJECT", "RULE overrides") \
                 .replace("Scan PROJECT", "RULE overrides") \
                 .replace("Scan Project", "RULE overrides")
        if new != txt:
            path.write_text(new, encoding="utf-8")
            print("[OK] MENU HTML:", path)
            changed += 1
    for path in root.rglob("*.js"):
        txt = path.read_text(encoding="utf-8")
        new = txt.replace("SCAN PROJECT", "RULE overrides") \
                 .replace("Scan PROJECT", "RULE overrides") \
                 .replace("Scan Project", "RULE overrides")
        if new != txt:
            path.write_text(new, encoding="utf-8")
            print("[OK] MENU JS:", path)
            changed += 1

if changed == 0:
    print("[WARN] MENU: không tìm thấy 'SCAN PROJECT' / 'Scan PROJECT' trong templates/static.")
else:
    print(f"[DONE] MENU: đã đổi text trong {changed} file.")
PY

########################################
# 3) THÊM BOX GHI CHÚ ISO 27001 / DEVSECOPS Ở SETTINGS
########################################
python3 - <<'PY'
from pathlib import Path

root = Path("templates")
if not root.exists():
    print("[WARN] SETTINGS: không có thư mục templates/")
else:
    for path in root.glob("*settings*.html"):
        html = path.read_text(encoding="utf-8")
        marker = "<!-- [settings_iso_notes_global_v1] -->"
        if marker in html:
            print("[i] SETTINGS:", path, "đã có block ISO, bỏ qua.")
            continue

        anchor = "Tool configuration loaded from <code>tool_config.json</code>."
        block = r"""
<!-- [settings_iso_notes_global_v1] -->
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
    <li><b>Exception &amp; RULE overrides</b>: các rule “accept risk” /
        “compensating controls” được quản lý trong tab <b>RULE overrides</b>,
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
        if anchor in html:
            html = html.replace(
                anchor,
                anchor + "\n" + block
            )
            print("[OK] SETTINGS:", path, "– chèn box ISO ngay dưới subtitle.")
        else:
            # Không thấy câu anchor, append box cuối file
            html = html.rstrip() + "\n" + block + "\n"
            print("[OK] SETTINGS:", path, "– không thấy subtitle, append box ISO cuối file.")

        path.write_text(html, encoding="utf-8")

# CSS chung cho box ghi chú
css_path = Path("static/css/security_resilient.css")
if css_path.exists():
    css = css_path.read_text(encoding="utf-8")
    marker = "/* [settings_iso_notes_global_v1] */"
    if marker not in css:
        extra = r"""
/* [settings_iso_notes_global_v1] – box ghi chú ISO 27001 / DevSecOps (CIO) */
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
        css = css.rstrip() + extra + "\n"
        css_path.write_text(css, encoding="utf-8")
        print("[OK] CSS: đã thêm style cho .sb-settings-notes vào", css_path)
    else:
        print("[i] CSS: .sb-settings-notes đã tồn tại.")
else:
    print("[WARN] Không tìm thấy static/css/security_resilient.css để thêm CSS box ISO.")
PY

echo "[i] === HOÀN TẤT patch_ui_green_menu_iso_final.sh ==="
