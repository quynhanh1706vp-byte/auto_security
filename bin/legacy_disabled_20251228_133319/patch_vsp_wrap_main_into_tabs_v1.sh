#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "${TPL}.bak_wrapmain_${TS}"
echo "[BACKUP] $TPL -> ${TPL}.bak_wrapmain_${TS}"

python3 - << 'PY'
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html")
text = tpl.read_text(encoding="utf-8")

if "id=\"vsp-tab-dashboard\"" in text:
    print("[INFO] Đã có vsp-tab-dashboard, không wrap nữa.")
    raise SystemExit(0)

start_idx = text.find("<main")
if start_idx == -1:
    print("[ERR] Không tìm thấy <main> trong template.")
    raise SystemExit(1)

gt_idx = text.find(">", start_idx)
if gt_idx == -1:
    print("[ERR] Không xác định được dấu '>' của <main>.")
    raise SystemExit(1)

end_idx = text.find("</main>")
if end_idx == -1:
    print("[ERR] Không tìm thấy </main> trong template.")
    raise SystemExit(1)

# Phần mở main: <main ...>
head = text[:gt_idx+1]
body = text[gt_idx+1:end_idx]
tail = text[end_idx:]

wrapper_start = """
  <div id="vsp-tab-dashboard" class="vsp-tab-pane vsp-tab-pane-active">
"""
wrapper_end_and_others = """
  </div> <!-- /#vsp-tab-dashboard -->

  <div id="vsp-tab-runs" class="vsp-tab-pane">
    <div class="vsp-card">
      <div class="vsp-card-body">
        <p>Runs &amp; Reports tab V1 – content TODO.</p>
      </div>
    </div>
  </div>

  <div id="vsp-tab-datasource" class="vsp-tab-pane">
    <div class="vsp-card">
      <div class="vsp-card-body">
        <p>Data Source tab V1 – content TODO.</p>
      </div>
    </div>
  </div>

  <div id="vsp-tab-settings" class="vsp-tab-pane">
    <div class="vsp-card">
      <div class="vsp-card-body">
        <p>Settings tab V1 – content TODO.</p>
      </div>
    </div>
  </div>

  <div id="vsp-tab-rules" class="vsp-tab-pane">
    <div class="vsp-card">
      <div class="vsp-card-body">
        <p>Rule Overrides tab V1 – content TODO.</p>
      </div>
    </div>
  </div>
"""

new_text = head + wrapper_start + body + wrapper_end_and_others + tail
tpl.write_text(new_text, encoding="utf-8")
print("[OK] Đã wrap toàn bộ <main> vào #vsp-tab-dashboard và tạo 4 pane còn lại.")
PY
