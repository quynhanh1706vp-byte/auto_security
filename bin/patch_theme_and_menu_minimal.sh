#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"

python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [fast_green_theme_minimal_v1] */"
if marker in css:
    print("[i] Đã có fast_green_theme_minimal_v1, bỏ qua.")
else:
    extra = """
/* [fast_green_theme_minimal_v1] – chỉ tô màu, không đổi layout */
:root {
  --sb-accent: #7CFC00;
  --sb-accent-soft: rgba(124,252,0,0.18);
}

/* Nền & card */
body {
  background: radial-gradient(circle at top, #122515 0%, #050a06 55%, #020405 100%) !important;
}
.sb-card, .card {
  border-color: rgba(124,252,0,0.35) !important;
  box-shadow: 0 0 14px rgba(124,252,0,0.16) !important;
}

/* KPI & nút */
.kpi-card, .kpi, .sb-kpi-card {
  border-color: rgba(124,252,0,0.35) !important;
  background: linear-gradient(135deg,
              rgba(124,252,0,0.18),
              rgba(0,0,0,0.18)) !important;
}
button, .btn, .sb-btn, .sb-btn-primary, .run-btn, .run-button {
  background: var(--sb-accent) !important;
  border-color: var(--sb-accent) !important;
  color: #021004 !important;
}
"""
    css = css.rstrip() + extra + "\\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã thêm fast_green_theme_minimal_v1 vào", path)
PY

# Đổi text menu
python3 - <<'PY'
from pathlib import Path

changed = 0
for path in Path("templates").rglob("*.html"):
    txt = path.read_text(encoding="utf-8")
    new = txt.replace("SCAN PROJECT", "RULE overrides") \
             .replace("Scan PROJECT", "RULE overrides") \
             .replace("Scan Project", "RULE overrides")
    if new != txt:
        path.write_text(new, encoding="utf-8")
        print("[OK] MENU HTML:", path)
        changed += 1

for path in Path("static").rglob("*.js"):
    txt = path.read_text(encoding="utf-8")
    new = txt.replace("SCAN PROJECT", "RULE overrides") \
             .replace("Scan PROJECT", "RULE overrides") \
             .replace("Scan Project", "RULE overrides")
    if new != txt:
        path.write_text(new, encoding="utf-8")
        print("[OK] MENU JS:", path)
        changed += 1

print("[i] MENU: số file đổi =", changed)
PY

echo "[DONE] patch_theme_and_menu_minimal.sh"
