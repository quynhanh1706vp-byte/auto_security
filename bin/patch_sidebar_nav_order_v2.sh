#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[i] ROOT = $ROOT"

TPLS=(
  "templates/index.html"
  "templates/runs.html"
  "templates/data_source.html"
  "templates/settings.html"
)

python3 - <<'PY'
import re, os

ROOT = "/home/test/Data/SECURITY_BUNDLE/ui"
tpls = [
    "templates/index.html",
    "templates/runs.html",
    "templates/data_source.html",
    "templates/settings.html",
]

# Sidebar mới (giống nhau cho mọi template)
new_sidebar = '''<div class="sb-sidebar">
  <div class="sb-logo">
    <div class="sb-logo-title">SECURITY BUNDLE</div>
    <div class="sb-logo-sub">Multi-tool offline scan</div>
  </div>

  <!-- MAIN -->
  <div class="nav-section">
    <div class="nav-section-title">MAIN</div>
    <div class="nav-item">
      <a href="/" class="nav-link">DASHBOARD Overview</a>
    </div>
  </div>

  <!-- RUNS & REPORTS – ngay sau MAIN -->
  <div class="nav-section">
    <div class="nav-section-title">RUNS &amp; REPORTS</div>
    <div class="nav-item">
      <a href="/runs" class="nav-link">History</a>
    </div>
  </div>

  <!-- DATA SOURCE -->
  <div class="nav-section">
    <div class="nav-section-title">DATA SOURCE</div>
    <div class="nav-item">
      <a href="/data_source" class="nav-link">JSON</a>
    </div>
  </div>

  <!-- SCAN PROJECT -->
  <div class="nav-section">
    <div class="nav-section-title">SCAN PROJECT</div>
    <div class="nav-item">
      <a href="/run_one" class="nav-link">RUN ONE PROJECT</a>
    </div>
  </div>

  <!-- SETTINGS -->
  <div class="nav-section">
    <div class="nav-section-title">SETTINGS</div>
    <div class="nav-item">
      <a href="/settings" class="nav-link">Tools</a>
    </div>
  </div>
</div>
<div class="sb-main">'''

pattern = re.compile(
    r'<div class="sb-sidebar">.*?<div class="sb-main">',
    re.DOTALL | re.UNICODE
)

for rel in tpls:
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        print(f"[WARN] Không tìm thấy {rel}, bỏ qua.")
        continue

    with open(path, encoding="utf-8") as f:
        data = f.read()

    new_data, n = pattern.subn(new_sidebar, data, count=1)

    if n == 0:
        print(f"[WARN] Không tìm thấy block sb-sidebar trong {rel}, không sửa.")
        continue

    with open(path, "w", encoding="utf-8") as f:
        f.write(new_data)

    print(f"[OK] Đã patch sidebar trong {rel}")
PY

echo "[DONE] patch_sidebar_nav_order_v2.sh hoàn thành."
