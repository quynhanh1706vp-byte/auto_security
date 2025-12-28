#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/base.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, re, os

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = f.read()

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

new_data, n = pattern.subn(new_sidebar, data, count=1)

if n == 0:
    print("[WARN] Không tìm thấy block sb-sidebar trong base.html, không sửa.")
else:
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_data)
    print("[OK] Đã patch sidebar trong base.html")
PY

echo "[DONE] patch_sidebar_nav_order_base.sh hoàn thành."
